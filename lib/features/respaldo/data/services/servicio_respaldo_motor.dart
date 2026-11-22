import 'dart:async';

import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../domain/entities/estado_respaldo_drive.dart';
import '../../domain/services/nivel_bateria.dart';
import '../../domain/services/servicio_respaldo.dart';

/// [ServicioRespaldo] sobre el [BackupService] del motor de sync (HU-SYNC-005, HU-SYNC-009).
///
/// Pone las condiciones de la app y deja el algoritmo al motor:
/// - **Automático**: Drive conectado con permiso, Wi-Fi y batería ≥ 30 % (R-SY10). Sin batería
///   informada, no se frena: no saber el nivel no puede dejar a nadie sin respaldo.
/// - **Pedido por la persona**: Drive conectado y conexión de cualquier tipo.
///
/// Lleva el estado de Drive de la fila «Cuenta Drive» (HU-SYNC-004): `401`/`403` lo pasa a
/// «Reconectar», sin espacio a «sin espacio», y un respaldo guardado lo saca de «sin espacio».
/// **Nada de lo que falla sale de acá como excepción** y nada que no sea un estado va a los logs:
/// ni cuentas, ni contenido, ni mensajes de Drive.
final class ServicioRespaldoMotor implements ServicioRespaldo {
  ServicioRespaldoMotor({
    required this._backup,
    required this._estadoDrive,
    required this._conexion,
    required this._bateria,
    required this._alPermisoRevocado,
    required this._alSinEspacio,
    required this._alGuardado,
    required this._alVerificar,
    DateTime Function()? ahora,
    this.esperaTrasFallo = const Duration(minutes: 30),
    AppLogger? logger,
  }) : _ahora = ahora ?? (() => DateTime.now().toUtc()),
       _log = logger ?? AppLogger.instance;

  final BackupService? Function() _backup;
  final Future<EstadoRespaldoDrive> Function() _estadoDrive;
  final Future<TipoConexion> Function() _conexion;
  final NivelBateria _bateria;
  final Future<void> Function() _alPermisoRevocado;
  final Future<void> Function() _alSinEspacio;
  final Future<void> Function() _alGuardado;
  final Future<void> Function(IntegrityReport informe) _alVerificar;
  final DateTime Function() _ahora;
  final AppLogger _log;

  /// Cuánto se espera para volver a intentar un respaldo **automático** que falló, para que cada
  /// vuelta a la app no repita una subida que no puede. El pedido de la persona no espera.
  final Duration esperaTrasFallo;

  /// Hay un respaldo o una verificación corriendo. Es un campo y no el estado del motor: la guarda
  /// tiene que cortar el segundo pedido aunque llegue antes de que el primero termine de armarse.
  bool _enCurso = false;

  DateTime? _ultimoFallo;

  @override
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen) async {
    if (_enCurso) return const RespaldoOmitido(MotivoOmision.enCurso);
    _enCurso = true;
    try {
      return await _respaldar(origen);
    } on Object catch (e) {
      // Leer el estado de Drive o la red falló antes de empezar: el pedido no puede romper a quien lo
      // hizo (el cierre de la jornada, la vuelta a la app).
      return RespaldoFallido(await _fallo(e, origen.name));
    } finally {
      _enCurso = false;
    }
  }

  Future<ResultadoRespaldo> _respaldar(OrigenRespaldo origen) async {
    final servicio = _backup();
    if (servicio == null) return const RespaldoOmitido(MotivoOmision.sinMotor);

    if (await _motivoParaNoCorrer(origen) case final motivo?) {
      _log.info(LogModulo.backup, 'BACKUP_OMITIDO', 'el respaldo espera', {
        'origen': origen.name,
        'motivo': motivo.name,
      });
      return RespaldoOmitido(motivo);
    }
    if (origen.esAutomatico && _enEsperaTrasUnFallo()) {
      return const RespaldoOmitido(MotivoOmision.falloReciente);
    }

    try {
      final entrada = await servicio.backupNow();
      _ultimoFallo = null;
      await _intentar(_alGuardado);
      _log.info(LogModulo.backup, 'BACKUP_OK', 'respaldo subido a Drive', {
        'origen': origen.name,
        'base': entrada.isBase,
        'bytes': entrada.bytes,
      });
      return RespaldoHecho(fecha: entrada.createdAt, esBase: entrada.isBase);
    } on Object catch (e) {
      return RespaldoFallido(await _fallo(e, origen.name));
    }
  }

  @override
  Future<ResultadoVerificacion> verificarIntegridad() async {
    if (_enCurso) return const VerificacionOmitida(MotivoOmision.enCurso);
    _enCurso = true;
    try {
      return await _verificar();
    } on Object catch (e) {
      return VerificacionFallida(await _fallo(e, 'verificacion'));
    } finally {
      _enCurso = false;
    }
  }

  Future<ResultadoVerificacion> _verificar() async {
    final servicio = _backup();
    if (servicio == null) return const VerificacionOmitida(MotivoOmision.sinMotor);
    if (await _motivoParaNoCorrer(OrigenRespaldo.alAbrir) case final motivo?) {
      return VerificacionOmitida(motivo);
    }

    final IntegrityReport informe;
    try {
      informe = await servicio.verifyIntegrity();
    } on Object catch (e) {
      // No poder mirar la cadena no es encontrarla rota: no se anota nada y se reintenta.
      return VerificacionFallida(await _fallo(e, 'verificacion'));
    }

    await _intentar(() => _alVerificar(informe));
    if (informe.ok) {
      _log.info(LogModulo.backup, 'BACKUP_INTEGRO', 'la cadena de respaldos está entera', {
        'hayRespaldo': informe.hasBackup,
        'entradas': informe.entries,
      });
      return CadenaIntegra(hayRespaldo: informe.hasBackup);
    }

    // Un problema: el motor ya dejó dicho que el próximo respaldo parte de una base nueva, y se
    // hace ahora (HU-SYNC-009, «Regenerando…»). Sin pedir de nuevo Wi-Fi ni batería: se acaban de
    // comprobar y la verificación misma ya usó la red.
    _log.warn(LogModulo.backup, 'BACKUP_PROBLEMA', 'la cadena de respaldos tiene un problema', {
      'problemas': informe.problems.toList()..sort(),
    });
    final ResultadoRespaldo regeneracion = await _regenerar(servicio);
    return CadenaConProblema(problemas: informe.problems, regeneracion: regeneracion);
  }

  Future<ResultadoRespaldo> _regenerar(BackupService servicio) async {
    try {
      final entrada = await servicio.backupNow();
      _ultimoFallo = null;
      await _intentar(_alGuardado);
      _log.info(LogModulo.backup, 'BACKUP_REGENERADO', 'base nueva subida a Drive', {
        'bytes': entrada.bytes,
      });
      return RespaldoHecho(fecha: entrada.createdAt, esBase: entrada.isBase);
    } on Object catch (e) {
      return RespaldoFallido(await _fallo(e, OrigenRespaldo.regeneracion.name));
    }
  }

  /// Por qué no se corre, o `null` si se puede.
  Future<MotivoOmision?> _motivoParaNoCorrer(OrigenRespaldo origen) async {
    final estado = await _estadoDrive();
    // Solo donde el permiso se supone vigente: ni sin cuenta, ni ya revocado.
    if (estado is! DriveConectada && estado is! DriveSinEspacio) return MotivoOmision.sinDrive;

    final red = await _conexion();
    if (red == TipoConexion.sinConexion) return MotivoOmision.sinConexion;
    if (!origen.esAutomatico) return null;
    if (red != TipoConexion.wifi) return MotivoOmision.sinWifi;

    final nivel = await _bateria.porcentaje();
    if (nivel != null && nivel < bateriaMinimaParaRespaldar) return MotivoOmision.bateriaBaja;
    return null;
  }

  bool _enEsperaTrasUnFallo() {
    final fallo = _ultimoFallo;
    return fallo != null && _ahora().difference(fallo) < esperaTrasFallo;
  }

  /// Traduce lo que salió mal, avisa a la fila de Drive y deja la causa en el log (sin datos).
  Future<CausaFalloRespaldo> _fallo(Object error, String origen) async {
    final causa = switch (error) {
      ArchiveUnauthorized() => CausaFalloRespaldo.permiso,
      ArchiveNoSpace() => CausaFalloRespaldo.sinEspacio,
      _ => CausaFalloRespaldo.otra,
    };
    _ultimoFallo = _ahora();
    _log.warn(LogModulo.backup, 'BACKUP_FALLO', 'el respaldo no se pudo subir', {
      'origen': origen,
      'causa': causa.name,
      // Solo el tipo: el mensaje de Drive puede nombrar la cuenta.
      'error': error.runtimeType.toString(),
    });
    switch (causa) {
      case CausaFalloRespaldo.permiso:
        await _intentar(_alPermisoRevocado);
      case CausaFalloRespaldo.sinEspacio:
        await _intentar(_alSinEspacio);
      case CausaFalloRespaldo.otra:
        break;
    }
    return causa;
  }

  /// Un aviso a la fila de Drive o al registro: si falla, no cambia cómo terminó el respaldo.
  Future<void> _intentar(Future<void> Function() accion) async {
    try {
      await accion();
    } on Object catch (e) {
      _log.warn(LogModulo.backup, 'BACKUP_AVISO', 'no se pudo anotar el resultado', {
        'error': e.runtimeType.toString(),
      });
    }
  }
}
