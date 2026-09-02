// Sincronización en segundo plano (RF-SY07, §5.2).
//
// El colportor cierra la app al terminar la jornada, sin señal. Sin esto, lo
// que anotó espera a que la vuelva a abrir; con esto sube cuando el sistema
// decide que hay red y batería, aunque la app esté cerrada.
//
// **El callback corre en otro isolate.** No hay pantalla, ni el motor de la
// app, ni nada que esté en memoria: hay que armar todo de cero. Eso es lo que
// obliga a que la sesión (`sesion.dart`), el `device_id` (`identidad.dart`) y
// la clave de la base vivan en el Keystore, y lo que hizo falta arreglar antes
// en `reclaimInFlight`: dos motores sobre la misma cola, uno acá y otro en el
// primer plano.

import 'package:flutter/widgets.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:workmanager/workmanager.dart';

import '../catalogo.dart';
import '../datos/abrir.dart';
import '../datos/db.dart';
import '../datos/drift_job_store.dart';
import '../datos/drift_local_store.dart';
import 'identidad.dart';
import 'sesion.dart';

/// Nombres del trabajo periódico. El `uniqueName` es lo que evita que se
/// registren dos si la app se abre varias veces.
const _unico = 'colportaje.sync.periodica';
const _tarea = 'sync';

/// Cada cuánto. Android no baja de 15 minutos: pedir menos lo sube igual, y
/// pedir mucho más no ahorra nada porque el sistema ya agrupa el trabajo de
/// todas las apps en las mismas ventanas.
const _frecuencia = Duration(minutes: 15);

/// Lo llama `main()` antes de correr la app.
Future<void> iniciarSegundoPlano() => Workmanager().initialize(despachador);

/// Registra el ciclo periódico. Idempotente por el `uniqueName`.
Future<void> registrarSyncPeriodica() => Workmanager().registerPeriodicTask(
      _unico,
      _tarea,
      frequency: _frecuencia,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        // Sin red no hay nada que hacer y despertar el proceso solo gasta
        // batería para descubrirlo.
        networkType: NetworkType.connected,
        // A propósito **no** se pide `requiresBatteryNotLow`: la batería baja
        // es justo el final de la jornada, que es cuando más ventas hay
        // esperando. Preferimos subirlas.
      ),
    );

Future<void> cancelarSyncPeriodica() =>
    Workmanager().cancelByUniqueName(_unico);

/// El punto de entrada del isolate de segundo plano.
///
/// `vm:entry-point` es obligatorio: sin eso el compilador AOT lo saca por no
/// encontrar quién lo llama, y la tarea falla en release y no en debug — que es
/// la peor combinación posible.
@pragma('vm:entry-point')
void despachador() {
  Workmanager().executeTask((tarea, datos) async {
    // El isolate arranca pelado: sin esto, cualquier plugin —Keystore, rutas,
    // SQLCipher— tira MissingPluginException.
    WidgetsFlutterBinding.ensureInitialized();
    return _unCiclo();
  });
}

/// Un ciclo completo, con todo armado y desarmado acá adentro.
///
/// Devuelve `true` siempre que no haya explotado algo inesperado. Un ciclo que
/// no pudo subir —sin red de verdad, el BFF caído— **no** es un `false`: el
/// motor ya tiene su política de reintento (los jobs quedan en `PENDING` y
/// salen al próximo trigger), y devolver `false` le sumaría el backoff de
/// WorkManager encima. Dos políticas de reintento peleando terminan
/// sincronizando cuando ninguna de las dos quería.
Future<bool> _unCiclo() async {
  final sesion = await leerSesion();
  // Todavía no se configuró nada: no hay a dónde sincronizar, y no es un error.
  if (sesion == null) return true;

  DbLocal? db;
  SyncEngine? motor;
  try {
    final conexion = await abrirDbCifrada();
    db = DbLocal(conexion.executor);

    motor = SyncEngine(
      specs: SpecRegistry(specsV1, allEntities: entidadesV1),
      transport: BffTransport(
        baseUrl: Uri.parse('${sesion.url}/'),
        token: () async => sesion.token,
        device: await sobreDeEsteDispositivo(),
      ),
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db),
      // Sin conectividad ni realtime: esto es un disparo único y se apaga
      // enseguida. Suscribirse a algo acá dejaría listeners colgados en un
      // isolate que está por morir.
    );

    await motor.syncNow();
    return true;
  } on Object {
    // Que una excepción escape del `executeTask` deja la tarea en un estado
    // que depende de la plataforma. Acá se corta: lo que había que sincronizar
    // sigue en la cola, en disco, esperando el próximo ciclo.
    return true;
  } finally {
    await motor?.dispose();
    await db?.close();
  }
}
