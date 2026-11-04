import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../../../core/secure_storage/custodia_clave_db.dart';
import '../../../../core/sync/armado_del_motor.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../plataforma/conectividad_del_motor.dart';
import '../../../auth/data/datasources/usuario_de_la_sesion_guardada.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../domain/entities/estado_respaldo_drive.dart';
import '../../domain/repositories/respaldo_drive_repository.dart';
import '../../domain/services/respaldo_nocturno.dart';
import '../../domain/services/servicio_respaldo.dart';
import '../datasources/auditoria_backup_local.dart';
import 'crypto_con_dek.dart';
import 'envoltorio_en_drive.dart';
import 'nivel_bateria_canal.dart';
import 'servicio_google.dart';
import 'servicio_respaldo_motor.dart';

/// Arma, **sin pantalla**, lo que el respaldo de la noche necesita (HU-SYNC-005, ADR-009, #583): se
/// ejecuta en el isolate que levanta el sistema con la app cerrada, donde no hay `ProviderScope`,
/// ni sesión de Supabase levantada, ni canales nativos propios de la app.
///
/// Los pasos, en este orden y cortando en el primero que no corresponde (devuelve `null`: hoy no
/// hay nada para respaldar):
/// 1. el usuario de la sesión guardada en el almacén seguro ([usuarioDeLaSesionGuardada]);
/// 2. que ese usuario tenga Drive conectado y con permiso;
/// 3. que exista la DB local y haya DEK en el Keystore (en iOS se lee con el equipo bloqueado,
///    `first_unlock_this_device`);
/// 4. abrir la DB cifrada con esa DEK ([DatabaseHelper]) y armar el motor con la **misma** receta
///    que la app ([armarMotorDeSync]), sin transporte de sync: de noche solo se respalda.
///
/// Dos diferencias con el respaldo de la app, a propósito:
/// - **El token de Drive no marca el permiso como revocado** si no llega. Pedirlo en silencio sin
///   una pantalla detrás puede fallar por razones que no son de la persona; el estado «Reconectar»
///   lo decide la app (`verificarPermiso`, al abrir Configuración) o un 401 de Drive. Sin token, el
///   respaldo falla y se reintenta.
/// - **Sin batería**: [NivelBateriaDesconocido]. El sistema solo despierta la tarea con el teléfono
///   cargando (restricción de la tarea) y una batería que no se puede leer no frena (R-SY10).
///
/// Una DB que no abre con la llave guardada, o de un esquema más nuevo que la app, no se toca ni se
/// reintenta de noche: la app lo resuelve al abrirse (HU-AUTH-009).
final class ArmadorDeRespaldoNocturno {
  ArmadorDeRespaldoNocturno({
    required this._almacen,
    required this._baseLocal,
    required this._custodia,
    required this._drive,
    required this._google,
    required this._conectividad,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final DatabaseHelper _baseLocal;
  final CustodiaClaveDb _custodia;
  final RespaldoDriveRepository _drive;
  final ServicioGoogle _google;
  final MonitorConectividad _conectividad;
  final AppLogger _log;

  Future<SesionDeRespaldoNocturno?> abrir() async {
    final usuarioId = await usuarioDeLaSesionGuardada(_almacen);
    if (usuarioId == null) return null;

    final estado = (await _drive.estado(usuarioId)).fold((falla) => throw falla, (e) => e);
    if (estado is! DriveConectada && estado is! DriveSinEspacio) return null;

    if (!await _baseLocal.existe()) return null;
    final dek = await _custodia.leerDek();
    if (dek == null) return null;

    final AppDatabase db;
    try {
      db = await _baseLocal.abrir(dek);
    } on ClaveDbIncorrectaException {
      _log.warn(
        LogModulo.backup,
        'BACKUP_NOCTURNO_DB',
        'la llave no abre la DB: lo resuelve la app',
      );
      return null;
    } on EsquemaDbPosteriorException {
      _log.warn(LogModulo.backup, 'BACKUP_NOCTURNO_DB', 'la DB es de una versión más nueva');
      return null;
    }

    try {
      final motor = armarMotorDeSync(
        db: db,
        leerDek: _custodia.leerDek,
        tokenDrive: _token,
        transporte: const TransporteSinBackend(),
        conectividad: ConectividadDelMotor(_conectividad),
      );
      final auditoria = AuditoriaBackupLocal(db);
      // La clave envuelta con la contraseña viaja con el respaldo (ADR-006, HU-SYNC-006): también el de
      // la noche la deja en Drive si no estaba. Nunca lanza.
      final cripto = CryptoConDek(_custodia.leerDek);
      final envoltorio = EnvoltorioEnDrive(
        envoltorios: () async => GoogleDriveArchive(token: _token, digest: cripto.digest),
        keyId: cripto.keyId,
        envoltorioLocal: _custodia.leerEnvoltorioCodificado,
        desactualizado: () async => await _custodia.envoltorioDesactualizadoPara() != null,
      );
      final servicio = ServicioRespaldoMotor(
        backup: () => motor.backup,
        estadoDrive: () async => (await _drive.estado(usuarioId)).fold((f) => throw f, (e) => e),
        conexion: _conectividad.actual,
        bateria: const NivelBateriaDesconocido(),
        alPermisoRevocado: () => _drive.marcarPermisoRevocado(usuarioId),
        alSinEspacio: () => _drive.marcarSinEspacio(usuarioId),
        alGuardado: () async {
          await _drive.marcarRespaldoGuardado(usuarioId);
          await envoltorio.sincronizar();
        },
        alVerificar: (informe) async => auditoria.registrar(
          cuando: informe.checkedAt,
          hayProblema: informe.needsRebase,
          problemas: informe.hasBackup ? informe.problems : const {'sin_respaldos'},
        ),
      );
      return _Sesion(servicio: servicio, auditoria: auditoria, motor: motor, base: _baseLocal);
    } on Object {
      await _baseLocal.cerrar();
      rethrow;
    }
  }

  /// El token de acceso de Drive, pedido en silencio. Sin token (o si el plugin falla) devuelve
  /// `null` y el archivo de Drive lo toma como «sin token», no como un permiso revocado.
  Future<String?> _token() async {
    try {
      return await _google.tokenSilencioso();
    } on Object catch (e) {
      _log.info(LogModulo.backup, 'BACKUP_NOCTURNO_TOKEN', 'no se pudo pedir el token de Drive', {
        'error': e.runtimeType.toString(),
      });
      return null;
    }
  }
}

final class _Sesion implements SesionDeRespaldoNocturno {
  _Sesion({
    required this.servicio,
    required this._auditoria,
    required this._motor,
    required this._base,
  });

  @override
  final ServicioRespaldo servicio;
  final AuditoriaBackupLocal _auditoria;
  final SyncEngine _motor;
  final DatabaseHelper _base;

  @override
  Future<DateTime?> ultimaVerificacion() => _auditoria.ultimaVerificacion();

  @override
  Future<void> cerrar() async {
    try {
      await _motor.dispose();
    } finally {
      await _base.cerrar();
    }
  }
}
