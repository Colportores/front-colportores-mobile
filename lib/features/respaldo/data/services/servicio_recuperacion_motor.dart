import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/secure_storage/envoltorio_dek.dart';
import '../../domain/services/servicio_recuperacion.dart';
import 'crypto_con_dek.dart';

/// [ServicioRecuperacion] sobre `SyncEngine.recover()` (contrato §7, HU-SYNC-006).
///
/// **Qué pone la app y qué el motor.** El motor baja las cadenas, las verifica, las fusiona por la
/// fecha de cada fila en **una sola transacción** (`DriftSnapshot.restoreChains`), reenvía la cola
/// restaurada y trae de Supabase lo que subió después. La app pone lo que el motor no sabe: de
/// **quién** son las cadenas que se restauran (las de otros teléfonos; la de este mismo no es algo
/// para traer), la **clave** que abre cada una (la DEK de aquel teléfono, desenvuelta con la
/// contraseña desde el envoltorio que viaja en Drive) y los resultados que la pantalla muestra.
///
/// **Varios respaldos** (decisión de Cristian, 03/11, «Varios resp.»): se recuperan todos los que la
/// contraseña abre y se fusionan, sin borrar nada. Los que no se abren (la contraseña no los abre, o
/// no tienen su clave envuelta en Drive) no frenan a los demás: el informe dice cuántos fueron y
/// siguen en Drive sin tocar, porque la recuperación no borra ni pisa ningún respaldo (decisión del
/// 04/11, #610 P1).
///
/// **Un motor aparte.** Mientras el asistente está abierto no hay motor de sync en la app
/// (`motorSyncProvider` es `null`, decisión de Cristian del 04/11, «Motor vivo»): la recuperación
/// arma el suyo con [_armarMotor] y lo cierra al terminar, salga como salga.
///
/// **Las claves de los teléfonos viejos no se quedan.** Se desenvuelven, se usan para descifrar y se
/// destruyen al terminar. Este teléfono sigue cifrando con su propia DEK: su respaldo arranca una
/// cadena propia, de una base completa, que ya incluye lo restaurado (decisión de Cristian, 03/11,
/// «Clave nueva»: dos teléfonos nunca comparten clave).
///
/// Nada de lo que pasa sale como excepción, y a los logs solo van tipos de error y contadores: ni
/// cuentas, ni contraseña, ni contenido.
final class ServicioRecuperacionMotor implements ServicioRecuperacion {
  ServicioRecuperacionMotor({
    required this._armarMotor,
    required this._archivo,
    required this._llavePropia,
    required this._abrirEnvoltorio,
    required this._snapshot,
    required this._hayConexion,
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? (() => DateTime.now().toUtc()),
       _log = logger ?? AppLogger.instance;

  /// Arma el motor con el que se recupera (con la DB abierta); `null` sin sesión. Se cierra al
  /// terminar cada recuperación.
  final SyncEngine? Function() _armarMotor;

  /// Drive; `null` si no hay un token vigente (sin conectar, permiso quitado).
  final Future<(ArchivePort, KeyEnvelopePort)?> Function() _archivo;

  final Future<String?> Function() _llavePropia;

  /// Desenvuelve la DEK de un envoltorio con la contraseña (`CustodiaClaveDb.abrirEnvoltorio`).
  final Future<ClaveDb> Function(EnvoltorioDek envoltorio, String password) _abrirEnvoltorio;

  /// La DB de este teléfono vista como archivo (`DriftSnapshot`).
  final SnapshotPort Function() _snapshot;

  final Future<bool> Function() _hayConexion;
  final DateTime Function() _ahora;
  final AppLogger _log;

  /// Lo ya bajado de un intento que se cortó por la red, por llave: el cifrado tal como está en
  /// Drive. Un «Reintentar» sigue desde la parte donde quedó en vez de bajar todo de nuevo. Se vacía
  /// al terminar de cualquier otra manera.
  final Map<String, BackupService> _bajadasPorLlave = {};

  /// La DEK abierta de cada cadena, mientras dura una recuperación. Los servicios guardados en
  /// [_bajadasPorLlave] la piden acá en cada descifrado; al terminar se destruyen.
  final Map<String, ClaveDb> _claves = {};

  @override
  Future<BusquedaRespaldo> buscar() async {
    try {
      final drive = await _archivo();
      if (drive == null) return const DriveSinPermiso();
      final (archivo, envoltorios) = drive;

      final propia = await _llavePropia();
      final ajenas = [
        for (final c in chainCandidates(await archivo.list()))
          if (c.keyId != propia) c,
      ];
      if (ajenas.isEmpty) return const SinRespaldoEnDrive();

      final conLlave = await envoltorios.envelopeKeyIds();
      final respaldos = [
        for (final c in ajenas)
          RespaldoEnDrive(
            llave: c.keyId,
            fecha: c.tip.createdAt,
            partes: c.parts,
            bytes: c.bytes,
            completo: c.intact,
            tieneLlave: c.keyId != null && conLlave.contains(c.keyId),
          ),
      ];
      if (respaldos.length == 1) return RespaldoEncontrado(respaldos.single);

      // Con más de uno no se elige por la persona: se recuperan todos los que la contraseña abra. Los
      // que no tienen su clave envuelta van igual en la lista: la pantalla los cuenta y el informe
      // dice cuántos no se pudieron abrir.
      _log.info(LogModulo.backup, 'RECUPERACION_VARIOS', 'hay más de un respaldo para traer', {
        'cadenas': respaldos.length,
        'abribles': respaldos.where((r) => r.tieneLlave).length,
      });
      return VariosRespaldosEnDrive(respaldos);
    } on Object catch (e) {
      _log.warn(LogModulo.backup, 'RECUPERACION_BUSQUEDA', 'no se pudo buscar el respaldo', {
        'error': e.runtimeType.toString(),
      });
      return switch (e) {
        ArchiveSinToken() || ArchiveUnauthorized() => const DriveSinPermiso(),
        _ when await _esDeRed(e) => const BusquedaSinConexion(),
        _ => const BusquedaFallida(),
      };
    }
  }

  /// La recuperación que está corriendo: una segunda (un doble toque que se coló) espera a que termine
  /// y no pisa las claves ni el motor de la primera.
  Future<void>? _enCurso;

  @override
  Future<ResultadoRecuperacion> recuperar({
    required List<RespaldoEnDrive> respaldos,
    required String password,
    void Function(ProgresoRecuperacion progreso)? alAvanzar,
    CancelacionRecuperacion? cancelar,
  }) async {
    final anterior = _enCurso;
    final esta = Completer<void>();
    _enCurso = esta.future;
    try {
      if (anterior != null) await anterior;
      return await _recuperar(respaldos, password, alAvanzar, cancelar);
    } finally {
      esta.complete();
    }
  }

  Future<ResultadoRecuperacion> _recuperar(
    List<RespaldoEnDrive> respaldos,
    String password,
    void Function(ProgresoRecuperacion progreso)? alAvanzar,
    CancelacionRecuperacion? cancelar,
  ) async {
    if (respaldos.isEmpty) return const RecuperacionFallida();

    SyncEngine? motor;
    var hechas = 0;
    var total = respaldos.fold<int>(0, (n, r) => n + r.partes);
    var conservarLoBajado = false;
    try {
      final drive = await _archivo();
      if (drive == null) return const RecuperacionSinPermiso();
      final (archivo, envoltorios) = drive;

      // 1. La clave de cada teléfono viejo, con la contraseña (Argon2id tarda 1 o 2 segundos cada una).
      final abiertas = <RespaldoEnDrive>[];
      final fallos = <_Fallo>[];
      for (final respaldo in respaldos) {
        if (cancelar?.cancelada ?? false) return const RecuperacionCancelada();
        final fallo = await _abrir(respaldo, password, envoltorios);
        if (fallo == null) {
          abiertas.add(respaldo);
        } else {
          fallos.add(fallo);
        }
      }
      if (abiertas.isEmpty) return _sinNingunaAbierta(fallos);
      total = abiertas.fold<int>(0, (n, r) => n + r.partes);
      if (cancelar?.cancelada ?? false) return const RecuperacionCancelada();

      // 2. Las cadenas de aquellos teléfonos, descifradas cada una con su clave. Un servicio por
      // cadena: guarda lo bajado si la red se corta.
      motor = _armarMotor();
      if (motor == null) return const RecuperacionFallida();
      final snapshot = _snapshot();
      final fuentes = [
        for (final respaldo in abiertas)
          RecoverySource(
            backup: _bajadasPorLlave[respaldo.llave!] ??= BackupService(
              archive: archivo,
              crypto: CryptoConDek(() async => _copiaDeLaClave(respaldo.llave!)),
              snapshot: snapshot,
            ),
            keyId: respaldo.llave,
          ),
      ];

      final informe = await motor.recover(
        sources: fuentes,
        cancel: _Cancelacion(cancelar),
        onProgress: (p) {
          if (p.phase == RecoveryPhase.downloading) {
            hechas = p.done;
            total = p.total;
          }
          alAvanzar?.call(_aProgreso(p));
        },
      );

      if (!informe.hadBackup) {
        _log.warn(LogModulo.backup, 'RECUPERACION_SIN_BASE', 'ninguna cadena tenía base usable', {
          'problema': informe.chainProblem,
          'cadenas': abiertas.length,
        });
        return const RespaldoIlegible();
      }
      // Los que no se abrieron con la contraseña y los que no tenían una base que leer: ninguno se
      // tocó en Drive.
      // Si el restore ya había pasado en un intento anterior, el motor no lo repite y no trae las
      // fechas: quedan contados los que la contraseña no abrió.
      final sinAbrir = informe.backupDates.isEmpty
          ? respaldos.length - abiertas.length
          : respaldos.length - informe.backupDates.length;
      _log.info(LogModulo.backup, 'RECUPERACION_OK', 'datos recuperados', {
        'parcial': informe.partial,
        'respaldos': informe.backupDates.length,
        'sinAbrir': sinAbrir,
        'partes': informe.partsRestored,
        'reenviados': informe.replayedJobs,
        'filas': informe.pulledRows,
      });
      return RecuperacionHecha(
        InformeRecuperacion(
          fechaDelRespaldo: informe.backupDate!,
          parcial: informe.partial,
          partesRestauradas: informe.partsRestored,
          partesTotales: informe.partsTotal,
          trabajosReenviados: informe.replayedJobs,
          filasTraidas: informe.pulledEntities,
          ahora: _ahora(),
          respaldosSinAbrir: sinAbrir,
        ),
      );
    } on Object catch (e) {
      _log.warn(LogModulo.backup, 'RECUPERACION_FALLO', 'la recuperación no terminó', {
        'error': e.runtimeType.toString(),
      });
      final porRed = await _esDeRed(e);
      conservarLoBajado = porRed && e is! RecoveryCancelled;
      return switch (e) {
        RecoveryCancelled() => const RecuperacionCancelada(),
        SnapshotNewerSchemaException(:final backupSchema, :final appSchema) =>
          RespaldoDeVersionMasNueva(esquemaDelRespaldo: backupSchema, esquemaDeLaApp: appSchema),
        SnapshotUnreadableException() || BackupIlegible() => const RespaldoIlegible(),
        ArchiveSinToken() || ArchiveUnauthorized() => const RecuperacionSinPermiso(),
        _ when porRed => RecuperacionSinConexion(hechas: hechas, total: total),
        _ => const RecuperacionFallida(),
      };
    } finally {
      for (final clave in _claves.values) {
        clave.destruir();
      }
      _claves.clear();
      if (!conservarLoBajado) _bajadasPorLlave.clear();
      if (motor != null) {
        try {
          await motor.dispose();
        } on Object catch (e) {
          _log.warn(LogModulo.backup, 'RECUPERACION_MOTOR', 'no se pudo cerrar el motor', {
            'error': e.runtimeType.toString(),
          });
        }
      }
    }
  }

  /// Abre la clave de [respaldo] con [password] y la deja en [_claves]; `null` si abrió, o por qué no.
  Future<_Fallo?> _abrir(
    RespaldoEnDrive respaldo,
    String password,
    KeyEnvelopePort envoltorios,
  ) async {
    final llave = respaldo.llave;
    if (llave == null || !respaldo.tieneLlave) return const _Fallo(_PorQueNoAbre.sinLlave);
    final bytes = await envoltorios.getEnvelope(llave);
    if (bytes == null) return const _Fallo(_PorQueNoAbre.sinLlave);
    final EnvoltorioDek envoltorio;
    try {
      envoltorio = EnvoltorioDek.decodificar(utf8.decode(bytes));
    } on EnvoltorioPosteriorException catch (e) {
      return _Fallo(_PorQueNoAbre.versionMasNueva, e.version);
    } on Object {
      return const _Fallo(_PorQueNoAbre.sinLlave);
    }
    try {
      _claves[llave]?.destruir();
      _claves[llave] = await _abrirEnvoltorio(envoltorio, password);
      return null;
    } on EnvoltorioNoAbreException {
      return const _Fallo(_PorQueNoAbre.contrasena);
    } on EnvoltorioCorruptoException {
      return const _Fallo(_PorQueNoAbre.sinLlave);
    }
  }

  /// Ninguna cadena se abrió: se dice la razón que la persona puede resolver primero (probar otra
  /// contraseña), después la de actualizar la app, después la de que Drive no tiene la clave.
  ResultadoRecuperacion _sinNingunaAbierta(List<_Fallo> fallos) {
    _log.warn(LogModulo.backup, 'RECUPERACION_SIN_LLAVE', 'ningún respaldo se pudo abrir', {
      'cadenas': fallos.length,
    });
    if (fallos.any((f) => f.motivo == _PorQueNoAbre.contrasena)) {
      return const ContrasenaNoAbreElRespaldo();
    }
    for (final f in fallos) {
      if (f.motivo == _PorQueNoAbre.versionMasNueva) {
        return RespaldoDeVersionMasNueva(
          esquemaDelRespaldo: f.version ?? EnvoltorioDek.versionActual + 1,
          esquemaDeLaApp: EnvoltorioDek.versionActual,
        );
      }
    }
    return const SinLlaveParaElRespaldo();
  }

  /// Una copia de la clave de [llave]: el cifrado destruye la que usa.
  ClaveDb _copiaDeLaClave(String llave) {
    final clave = _claves[llave];
    if (clave == null || clave.destruida) {
      throw StateError('la clave de la cadena ya no está');
    }
    return ClaveDb(Uint8List.fromList(clave.bytes));
  }

  /// Una caída de la red: la del socket, la del tiempo de espera, la de `package:http`, la del
  /// transporte de Supabase (transitoria), o cualquier falla con el teléfono sin conexión.
  Future<bool> _esDeRed(Object e) async =>
      e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException ||
      (e is TransportFailure && e.kind == FailureKind.transient) ||
      !await _hayConexion();

  static ProgresoRecuperacion _aProgreso(RecoveryProgress p) => ProgresoRecuperacion(
    switch (p.phase) {
      RecoveryPhase.searching => PasoRecuperacion.buscando,
      RecoveryPhase.downloading => PasoRecuperacion.bajando,
      RecoveryPhase.applying => PasoRecuperacion.aplicando,
      RecoveryPhase.replaying => PasoRecuperacion.reenviando,
      RecoveryPhase.reconciling => PasoRecuperacion.reconciliando,
      RecoveryPhase.done => PasoRecuperacion.listo,
    },
    hechas: p.done,
    total: p.total,
    esperandoConexion: p.waitingForNetwork,
  );
}

/// Por qué no se pudo abrir la clave de un respaldo.
enum _PorQueNoAbre {
  /// La contraseña no es la que armó el envoltorio.
  contrasena,

  /// Drive no tiene la clave envuelta (o está dañada): ninguna contraseña lo abre.
  sinLlave,

  /// El envoltorio es de una versión de la app más nueva que esta.
  versionMasNueva,
}

/// Un respaldo que no se pudo abrir y por qué ([version] es la del envoltorio, si es más nuevo).
final class _Fallo {
  const _Fallo(this.motivo, [this.version]);

  final _PorQueNoAbre motivo;
  final int? version;
}

/// Une la cancelación de la app con la del motor: el motor la mira entre parte y parte.
final class _Cancelacion extends RecoveryCancelToken {
  _Cancelacion(this._desdeLaApp);

  final CancelacionRecuperacion? _desdeLaApp;

  @override
  bool get isCancelled => super.isCancelled || (_desdeLaApp?.cancelada ?? false);
}
