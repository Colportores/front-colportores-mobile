import 'package:flutter/material.dart';

import '../../../auth/domain/usecases/borrar_datos_locales_use_case.dart' show PasoBorrado;
import '../pages/borrar_datos_locales_page.dart' show TextosBorrado;

/// Artboard 06: «Borrando datos». Los tres pasos con su estado y «No cierres la app.».
class BorrandoDatos extends StatelessWidget {
  const BorrandoDatos({super.key, required this.paso});

  final PasoBorrado paso;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Pisar y eliminar la base es un solo trabajo: los dos pasos pasan juntos a hechos.
    final (estadoPisando, estadoEliminando, estadoCerrando) = switch (paso) {
      PasoBorrado.borrandoDatos => (
        _EstadoPaso.enCurso,
        _EstadoPaso.pendiente,
        _EstadoPaso.pendiente,
      ),
      PasoBorrado.cerrandoSesion => (_EstadoPaso.hecho, _EstadoPaso.hecho, _EstadoPaso.enCurso),
    };

    return Column(
      key: const Key('borrar_datos_borrando'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            'Borrando datos',
            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
          ),
        ),
        const SizedBox(height: 24),
        _Paso(texto: 'Pisando el archivo con ceros', estado: estadoPisando),
        _Paso(texto: 'Eliminando la base local', estado: estadoEliminando),
        _Paso(texto: 'Cerrando tu sesión', estado: estadoCerrando),
        const SizedBox(height: 24),
        Text(
          TextosBorrado.noCierresLaApp,
          key: const Key('borrar_datos_no_cierres'),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

enum _EstadoPaso { hecho, enCurso, pendiente }

class _Paso extends StatelessWidget {
  const _Paso({required this.texto, required this.estado});

  final String texto;
  final _EstadoPaso estado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icono, descripcion) = switch (estado) {
      _EstadoPaso.hecho => (Icon(Icons.check_circle, color: theme.colorScheme.primary), 'hecho'),
      _EstadoPaso.enCurso => (
        const SizedBox.square(
          dimension: 24,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
        'en curso',
      ),
      _EstadoPaso.pendiente => (const Icon(Icons.radio_button_unchecked), 'pendiente'),
    };
    return Semantics(
      container: true,
      label: '$texto, $descripcion',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox.square(dimension: 24, child: icono),
            const SizedBox(width: 12),
            Expanded(child: Text(texto, style: theme.textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

/// Artboard 07: los datos del teléfono se borraron pero el backup en Drive no. Los datos locales
/// nunca se restauran por una falla en Drive (HU-AUTH-010): desde acá solo se reintenta Drive o se
/// va al login.
class FallaBackupDrive extends StatelessWidget {
  const FallaBackupDrive({
    super.key,
    required this.mensaje,
    required this.reintentando,
    required this.onReintentar,
    required this.onIrAlLogin,
  });

  final String mensaje;
  final bool reintentando;
  final VoidCallback onReintentar;
  final VoidCallback onIrAlLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('borrar_datos_falla_drive'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ExcludeSemantics(child: Icon(Icons.check_circle, color: theme.colorScheme.primary)),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Datos de este teléfono borrados', style: theme.textTheme.titleMedium),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ExcludeSemantics(
              child: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Backup en Drive sin borrar', style: theme.textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          mensaje,
          key: const Key('borrar_datos_aviso_drive'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('borrar_datos_drive_reintentar'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: reintentando ? null : onReintentar,
          child: const Text('Reintentar'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('borrar_datos_ir_al_login'),
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: reintentando ? null : onIrAlLogin,
          child: const Text('Ir al login'),
        ),
      ],
    );
  }
}

/// Artboard 08: el borrado falló. [mensaje] dice si se borró algo o no: «No se borró nada y tu
/// sesión sigue abierta» solo si es cierto.
class ErrorAlBorrar extends StatelessWidget {
  const ErrorAlBorrar({
    super.key,
    required this.mensaje,
    required this.onReintentar,
    required this.onVolver,
  });

  final String mensaje;
  final VoidCallback onReintentar;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('borrar_datos_error'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ExcludeSemantics(child: Icon(Icons.error_outline, color: theme.colorScheme.error)),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                liveRegion: true,
                child: Text('No pudimos borrar tus datos', style: theme.textTheme.titleMedium),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          mensaje,
          key: const Key('borrar_datos_error_mensaje'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('borrar_datos_reintentar'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: onReintentar,
          child: const Text('Reintentar'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('borrar_datos_volver_configuracion'),
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: onVolver,
          child: const Text('Volver a Configuración'),
        ),
      ],
    );
  }
}
