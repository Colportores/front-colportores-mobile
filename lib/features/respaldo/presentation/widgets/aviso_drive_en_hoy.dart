import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/respaldo_drive_providers.dart';
import '../textos_respaldo_drive.dart';
import 'aviso_drive.dart';

/// La franja del Drive en Hoy (HU-SYNC-004, vista 16, 16F·01 a 16F·04, #550): avisa que el respaldo
/// dejó de hacerse porque Google ya no da el permiso (16F·01) o porque el Drive está lleno (16F·02),
/// y lleva a Configuración, donde se resuelve (16D·06 y 16D·10). Con otra cuenta de Google por
/// confirmar (16E) el respaldo está frenado hasta que elija: la franja lo dice y «Elegir cuenta» abre
/// la hoja (decisión del 23/11, R7).
///
/// Dura lo que dure el problema. Se puede ocultar hasta mañana (16F·04): mientras tanto el engranaje
/// de Hoy lleva la marca roja y la fila «Cuenta Drive» sigue en rojo. Sin problema, o con la franja
/// oculta, no ocupa lugar.
///
/// Es un aviso más de la franja de Hoy (vista 25): va primero, porque avisa de datos sin copia.
class AvisoDriveEnHoy extends ConsumerStatefulWidget {
  const AvisoDriveEnHoy({
    super.key,
    required this.alAbrirConfiguracion,
    required this.alElegirCuenta,
  });

  /// «Reconectar en Configuración» y «Ver en Configuración».
  final VoidCallback alAbrirConfiguracion;

  /// «Elegir cuenta» (otra cuenta de Google por confirmar): abre la misma hoja que la fila «Cuenta
  /// Drive» de Configuración.
  final VoidCallback alElegirCuenta;

  @override
  ConsumerState<AvisoDriveEnHoy> createState() => _AvisoDriveEnHoyState();
}

class _AvisoDriveEnHoyState extends ConsumerState<AvisoDriveEnHoy> {
  /// Se está ocultando. Es un campo y no solo el estado: la guarda tiene que cortar el segundo toque
  /// aunque llegue antes de que se vuelva a dibujar.
  bool _ocultando = false;

  Future<void> _ocultar() async {
    if (_ocultando) return;
    setState(() => _ocultando = true);
    var anotado = false;
    try {
      anotado = await ref.read(franjaDriveOcultaProvider.notifier).ocultar();
    } on Object {
      // `ocultar` no lanza; si algún día lo hiciera, el botón no puede quedar apagado para siempre.
    } finally {
      if (mounted) setState(() => _ocultando = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: Key(anotado ? 'aviso_drive_oculto' : 'aviso_drive_no_oculto'),
          content: Text(
            anotado ? TextosRespaldoDrive.franjaOculta : TextosRespaldoDrive.noPudimosOcultar,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final problema = leerFranjaDriveEnHoy(ref).franja;
    if (problema == null) return const SizedBox.shrink();
    final (clase, texto, accion, alAccionar) = switch (problema) {
      ProblemaDeRespaldoEnHoy.permisoRevocado => (
        ClaseAvisoDrive.error,
        TextosRespaldoDrive.franjaRevocada,
        TextosRespaldoDrive.franjaReconectarEnConfiguracion,
        widget.alAbrirConfiguracion,
      ),
      ProblemaDeRespaldoEnHoy.sinEspacio => (
        ClaseAvisoDrive.advertencia,
        TextosRespaldoDrive.franjaDriveLleno,
        TextosRespaldoDrive.franjaVerEnConfiguracion,
        widget.alAbrirConfiguracion,
      ),
      ProblemaDeRespaldoEnHoy.cuentaPorConfirmar => (
        ClaseAvisoDrive.advertencia,
        TextosRespaldoDrive.franjaFrenada,
        TextosRespaldoDrive.franjaElegirCuenta,
        widget.alElegirCuenta,
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AvisoDrive(
        key: Key('aviso_drive_en_hoy_${problema.name}'),
        clase: clase,
        texto: texto,
        accion: accion,
        alAccionar: alAccionar,
        accionSecundaria: TextosRespaldoDrive.ocultarHastaManiana,
        alAccionarSecundaria: _ocultando ? null : () => unawaited(_ocultar()),
      ),
    );
  }
}
