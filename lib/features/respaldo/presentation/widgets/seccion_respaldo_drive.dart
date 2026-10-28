import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, AsyncError, AsyncLoading, AsyncValue;

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/estado_respaldo_drive.dart';
import '../textos_respaldo_drive.dart';
import 'aviso_drive.dart';

/// La sección «Respaldo» de Configuración con la fila «Cuenta Drive» (vista 16, 16D·01, 04, 06 y
/// 10). No decide nada: dibuja el [estado] y avisa qué tocó la persona.
class SeccionRespaldoDrive extends StatelessWidget {
  const SeccionRespaldoDrive({
    super.key,
    required this.estado,
    required this.ultimoRespaldo,
    required this.ahora,
    required this.alConectar,
    required this.alVerCuenta,
    required this.alReintentar,
  });

  final AsyncValue<EstadoRespaldoDrive> estado;

  /// Cuándo se hizo el último respaldo, si se sabe (`null` = todavía no hubo, o no se sabe).
  final DateTime? ultimoRespaldo;

  /// La hora de ahora, para decir «hoy» o «ayer».
  final DateTime ahora;

  /// «Conectar» o «Reconectar».
  final VoidCallback alConectar;

  /// Tocó la fila con Drive conectado: lleva a desconectar.
  final VoidCallback alVerCuenta;

  /// «Reintentar» cuando no se pudo leer el estado.
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final actual = estado.value;
    final conProblema = actual is DrivePermisoRevocado || actual is DriveSinEspacio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Semantics(
            header: true,
            child: Text(TextosRespaldoDrive.seccion, style: theme.textTheme.titleMedium),
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: conProblema ? theme.colorScheme.error : colores.borde,
              width: conProblema ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: _Fila(
            estado: estado,
            ultimoRespaldo: ultimoRespaldo,
            ahora: ahora,
            alConectar: alConectar,
            alVerCuenta: alVerCuenta,
            alReintentar: alReintentar,
          ),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.estado,
    required this.ultimoRespaldo,
    required this.ahora,
    required this.alConectar,
    required this.alVerCuenta,
    required this.alReintentar,
  });

  final AsyncValue<EstadoRespaldoDrive> estado;
  final DateTime? ultimoRespaldo;
  final DateTime ahora;
  final VoidCallback alConectar;
  final VoidCallback alVerCuenta;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final error = theme.colorScheme.error;
    final TextStyle? lineaChica = theme.textTheme.bodySmall?.copyWith(color: colores.gris);
    final TextStyle? lineaDeProblema = theme.textTheme.bodySmall?.copyWith(
      color: error,
      fontWeight: FontWeight.w600,
    );
    final TextStyle accion = (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    const chevron = Icon(Icons.chevron_right);

    final Widget leading;
    final List<Widget> lineas;
    final Widget? trailing;
    final VoidCallback? alTocar;

    switch (estado) {
      case AsyncError():
        leading = const _Glifo(icono: Icons.cloud_off_outlined);
        lineas = [Text(TextosRespaldoDrive.noPudimosVer, style: lineaDeProblema)];
        trailing = Text(TextosRespaldoDrive.reintentar, style: accion);
        alTocar = alReintentar;
      case AsyncData(value: final EstadoRespaldoDrive e):
        switch (e) {
          case DriveSinConectar():
            leading = const _Glifo(icono: Icons.cloud_outlined);
            lineas = [Text(TextosRespaldoDrive.sinConectar, style: lineaDeProblema)];
            trailing = Text(TextosRespaldoDrive.conectar, style: accion);
            alTocar = alConectar;
          case DriveConectada(:final email):
            leading = const _Glifo(
              icono: Icons.cloud_done_outlined,
              fondo: Color(0xFFDDE8D3),
              color: Color(0xFF1F6E3A),
            );
            lineas = [
              _Correo(email, estilo: lineaChica),
              Text(
                ultimoRespaldo == null
                    ? TextosRespaldoDrive.sinRespaldoTodavia
                    : TextosRespaldoDrive.ultimoRespaldo(ultimoRespaldo!.toLocal(), ahora),
                key: const Key('configuracion_drive_ultimo'),
                style: lineaChica,
              ),
            ];
            trailing = chevron;
            alTocar = alVerCuenta;
          case DrivePermisoRevocado(:final email):
            leading = _Glifo(icono: Icons.priority_high, fondo: error, color: Colors.white);
            lineas = [
              _Correo(email, estilo: lineaChica),
              Text(TextosRespaldoDrive.permisoRevocado, style: lineaDeProblema),
            ];
            trailing = Text(TextosRespaldoDrive.reconectar, style: accion);
            alTocar = alConectar;
          case DriveSinEspacio(:final email):
            leading = _Glifo(icono: Icons.priority_high, fondo: error, color: Colors.white);
            lineas = [
              _Correo(email, estilo: lineaChica),
              Text(TextosRespaldoDrive.sinEspacio, style: lineaDeProblema),
            ];
            trailing = chevron;
            alTocar = alVerCuenta;
        }
      case AsyncLoading():
        leading = const _Glifo(icono: Icons.cloud_outlined);
        lineas = [Text(TextosRespaldoDrive.revisando, style: lineaChica)];
        trailing = const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: 'Revisando'),
        );
        alTocar = null;
    }

    // Con la letra grande la acción de texto («Conectar», «Reconectar», «Reintentar») deja de
    // ir a la derecha, donde se come la mitad del ancho y parte el título y el correo: pasa a un
    // renglón propio de al menos 48 dp. A tamaño normal queda como en el canvas.
    final letraGrande = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final accionAparte = letraGrande && trailing is Text;

    Widget fila = ListTile(
      key: const Key('configuracion_drive_fila'),
      minVerticalPadding: 12,
      leading: ExcludeSemantics(child: leading),
      title: const Text(TextosRespaldoDrive.fila),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lineas),
      trailing: accionAparte ? null : trailing,
      onTap: alTocar,
    );
    // Quien usa lector de pantalla tiene que saber que tocar la fila conectada lleva a desconectar.
    if (identical(trailing, chevron)) {
      fila = Semantics(hint: TextosRespaldoDrive.pistaDesconectar, child: fila);
    }
    if (!accionAparte) return fila;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fila,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 8, bottom: 4),
            child: TextButton(
              key: const Key('configuracion_drive_accion'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: alTocar,
              child: Text(trailing.data!, style: accion),
            ),
          ),
        ),
      ],
    );
  }
}

/// El correo de la cuenta de Google se lee entero, nunca con «…»: si no entra se parte.
class _Correo extends StatelessWidget {
  const _Correo(this.email, {required this.estilo});

  final String email;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    return Text(email, key: const Key('configuracion_drive_correo'), style: estilo);
  }
}

class _Glifo extends StatelessWidget {
  const _Glifo({required this.icono, this.fondo, this.color});

  final IconData icono;
  final Color? fondo;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 20,
      backgroundColor: fondo ?? theme.colorScheme.surfaceContainerHighest,
      foregroundColor: color ?? theme.colorScheme.primary,
      child: Icon(icono, size: 22),
    );
  }
}

/// El aviso de arriba de Configuración (16D·06 y 16D·07): el permiso se perdió, o la persona cerró
/// la pantalla de Google. Sin ninguno de los dos no ocupa lugar.
class AvisoRespaldoDrive extends StatelessWidget {
  const AvisoRespaldoDrive({
    super.key,
    required this.estado,
    required this.cancelado,
    required this.alReconectar,
  });

  final EstadoRespaldoDrive? estado;
  final bool cancelado;
  final VoidCallback alReconectar;

  @override
  Widget build(BuildContext context) {
    if (estado is DrivePermisoRevocado) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: AvisoDrive(
          key: const Key('configuracion_drive_aviso_revocado'),
          clase: ClaseAvisoDrive.error,
          texto: TextosRespaldoDrive.avisoRevocado,
          accion: TextosRespaldoDrive.reconectar,
          alAccionar: alReconectar,
        ),
      );
    }
    if (cancelado && estado is DriveSinConectar) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: AvisoDrive(
          key: Key('configuracion_drive_aviso_cancelado'),
          clase: ClaseAvisoDrive.info,
          texto: TextosRespaldoDrive.avisoCancelado,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
