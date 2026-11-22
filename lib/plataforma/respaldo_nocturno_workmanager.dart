import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../core/conectividad/monitor_conectividad_plus.dart';
import '../core/config/config_google.dart';
import '../core/database/database_helper.dart';
import '../core/secure_storage/almacen_seguro_keystore.dart';
import '../core/secure_storage/archivo_envoltorio_dek.dart';
import '../core/secure_storage/cripto_sodium.dart';
import '../core/secure_storage/custodia_clave_db.dart';
import '../features/respaldo/data/repositories/respaldo_drive_repository_impl.dart';
import '../features/respaldo/data/services/armador_respaldo_nocturno.dart';
import '../features/respaldo/data/services/programador_nocturno_del_sistema.dart';
import '../features/respaldo/data/services/servicio_google.dart';
import '../features/respaldo/data/services/servicio_google_sign_in.dart';
import '../features/respaldo/domain/services/respaldo_nocturno.dart';

// El respaldo de la noche con la app cerrada (HU-SYNC-005, ADR-009, #583): lo único de la app que
// conoce el plugin `workmanager` (WorkManager en Android, BGTaskScheduler en iOS). Es una pieza
// fina y sin lógica, como `ServicioGoogleSignIn`: no se prueba en la VM, que no tiene ni WorkManager
// ni BGTaskScheduler; lo que decide qué, cuándo y qué hacer con cada resultado está probado en
// `ProgramadorNocturnoDelSistema`, `RespaldoNocturno` y `ArmadorDeRespaldoNocturno`.

/// El punto de entrada del isolate de segundo plano. El sistema lo despierta sin la app abierta:
/// no hay `runApp`, ni `ProviderScope`, ni `main()`. `Workmanager.initialize` (en `main.dart`) le
/// pasa este símbolo al plugin, que lo guarda por su nombre para volver a levantarlo.
@pragma('vm:entry-point')
void despachadorDeSegundoPlano() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((tarea, datos) async {
    if (tarea != nombreTareaRespaldoNocturno) return true;
    return correrElRespaldoNocturno();
  });
}

/// Arma lo que el respaldo necesita con lo que tiene el isolate de segundo plano (el almacén seguro,
/// el archivo de la DB, las credenciales de Google) y corre. `true` si no hay nada más que hacer;
/// `false` pide al sistema que vuelva a intentar (Android: su espera creciente).
///
/// En iOS el sistema no repite la tarea: se deja programada la de la noche siguiente.
Future<bool> correrElRespaldoNocturno() async {
  try {
    final almacen = AlmacenSeguroKeystore();
    final cripto = CriptoSodium();
    final ServicioGoogle google = ConfigGoogle.configurada
        ? ServicioGoogleSignIn()
        : const ServicioGoogleSinConfigurar();
    final armador = ArmadorDeRespaldoNocturno(
      almacen: almacen,
      baseLocal: DatabaseHelper(
        directorio: getApplicationDocumentsDirectory,
        directorioTemporal: getTemporaryDirectory,
        // El mismo archivo que usa la app, desde otro isolate: si coincide con una escritura suya,
        // espera un momento al candado en vez de fallar con «database is locked».
        esperaDeBloqueo: const Duration(seconds: 5),
      ),
      custodia: CustodiaClaveDb(
        almacen,
        ArchivoEnvoltorioDek(directorio: getApplicationDocumentsDirectory),
        cripto,
        cripto,
      ),
      drive: RespaldoDriveRepositoryImpl(almacen, google),
      google: google,
      conectividad: MonitorConectividadPlus(),
    );
    final desenlace = await RespaldoNocturno(abrir: armador.abrir).ejecutar();
    return desenlace == DesenlaceNocturno.terminado;
  } on Object {
    return false;
  } finally {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await ProgramadorNocturnoDelSistema(TareasWorkmanager(), esIos: true).programar();
    }
  }
}

/// [TareasDelSistema] sobre `workmanager`.
final class TareasWorkmanager implements TareasDelSistema {
  TareasWorkmanager({Workmanager? workmanager}) : _wm = workmanager ?? Workmanager();

  final Workmanager _wm;

  /// Registra el despachador ante el plugin. Una vez, antes de programar nada (en `main.dart`).
  static Future<void> iniciar() => Workmanager().initialize(despachadorDeSegundoPlano);

  @override
  Future<void> periodica({
    required String nombre,
    required Duration cada,
    required Duration primeraEspera,
    required bool soloWifi,
    required bool cargando,
  }) => _wm.registerPeriodicTask(
    nombre,
    nombre,
    frequency: cada,
    initialDelay: primeraEspera,
    constraints: Constraints(
      networkType: soloWifi ? NetworkType.unmetered : NetworkType.connected,
      requiresCharging: cargando,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );

  @override
  Future<void> unaVez({
    required String nombre,
    required Duration espera,
    required bool conRed,
    required bool cargando,
  }) => _wm.registerProcessingTask(
    nombre,
    nombre,
    initialDelay: espera,
    constraints: Constraints(
      networkType: conRed ? NetworkType.connected : NetworkType.notRequired,
      requiresCharging: cargando,
    ),
  );

  @override
  Future<void> cancelar(String nombre) => _wm.cancelByUniqueName(nombre);
}
