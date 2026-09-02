# sync_engine

Motor de sincronización y backup de Colportaje App.
Implementa el [Contrato del motor de sincronización](../../../../back/) v0.9.2.

Núcleo Dart puro (§5.9): corre en la VM, sin emulador ni dispositivo.

```bash
dart pub get
dart test        # ~1 s
```

> **Ubicación**: el contrato lo pone en `front-colportores-mobile/packages/sync_engine`.
> Está acá dentro del prototipo hasta que exista ese repo; mover el directorio
> es todo lo que hace falta.

## Estado

| Pieza del contrato | Estado |
|---|---|
| §2, §3 — las tres políticas, `SyncSpec`, registro validado al arrancar | ✅ [`core/spec.dart`](lib/src/core/spec.dart) |
| §3 — `stage()`, `syncNow()`, `status`, `requeue()`, `setDataSaver()` | ✅ [`core/engine.dart`](lib/src/core/engine.dart) |
| §5.1 — estados `PENDING`/`IN_FLIGHT`/`INVALID`/`DONE`, sin retry counter | ✅ |
| RF-SY06 — `engine.errorQueue()`: la cola de error, con código y job | ✅ |
| §5.2 — triggers: conectividad, app resumed, escritura crítica. Sin timer | ✅ |
| §5.3 — idempotencia por `client_op_id` + PK v7 | ✅ |
| §5.4 — conflictos LWW por `sync_version` | ✅ |
| §5.5 — orden por entidad y lotes por bytes | ✅ [`core/batch.dart`](lib/src/core/batch.dart) |
| §5.8 — purga de `DONE` a los 7 días | ✅ |
| §6 — `FakeSyncTransport` | ✅ [`testing/`](lib/src/testing/) |
| §5.7, ADR-003 — backup incremental E2E, cadena verificable, restore | ✅ [`core/backup.dart`](lib/src/core/backup.dart), [`core/backup_service.dart`](lib/src/core/backup_service.dart) |
| §7 — `recover()`: restore + replay + reconciliación + reporte | ✅ |
| §3 — `SyncTableAdapter` y `stageRow()` tipado | ✅ [`core/adapter.dart`](lib/src/core/adapter.dart) |
| §5.3, §7 — UUID v7 generado en el dispositivo | ✅ [`core/uuid.dart`](lib/src/core/uuid.dart) |
| §8 — suite de conformidad, **publicada para el CI de la app** | ✅ [`lib/conformance.dart`](lib/conformance.dart) |
| R-A1, R-A2 | ✅ automatizadas |
| §5.6 — realtime: evento → delta por REST → DB local | ✅ |
| §6 — `BffTransport`: el camino batch por HTTP | ✅ [`adapters/bff_transport.dart`](lib/src/adapters/bff_transport.dart) |
| ADR-003 — compresión, SHA-256 e `Isolate.run` del backup | ✅ [`adapters/backup_codec.dart`](lib/src/adapters/backup_codec.dart) |
| ADR-003, §6 — `DriveArchive`: el `appDataFolder` por HTTP, con la cadena en `appProperties` | ✅ [`adapters/drive_archive.dart`](lib/src/adapters/drive_archive.dart) |
| `JobStorePort`, `LocalStorePort`, `SnapshotPort` sobre Drift + SQLCipher | ✅ en la app ([`lib/datos/`](../../lib/datos/)), pasando `port_contracts` |
| RF-AL06 — `AesGcmCrypto`: AES-256-GCM sobre el bloque comprimido | ✅ [`adapters/aes_gcm_crypto.dart`](lib/src/adapters/aes_gcm_crypto.dart) |
| Adaptadores de plataforma: los cinco plugins, y la aceleración nativa del cifrado | ❌ |

Las únicas dependencias de producción son `test` (la suite de §8 se publica) y
`http` (`BffTransport` y `DriveArchive`). Las dos son Dart puro: `dart pub get` no baja nada de
Flutter y toda la suite corre en la VM.

## Estructura

```
lib/
  sync_engine.dart          API pública
  conformance.dart          la suite que corre en el CI de la app (§8)
  port_contracts.dart       lo que toda implementación de un puerto debe cumplir
  testing.dart              fakes (import aparte, como package:http/testing.dart)
  src/core/                 Dart puro
    spec.dart               las tres políticas y el registro
    engine.dart             el ciclo: claim → lotes → push → resultados → pull
                            y recover(): las cinco fases de §7
    backup.dart             la cadena y su verificación
    backup_service.dart     backupNow / verifyChain / restore
    recover.dart            RecoveryReport, LostWindow
    batch.dart              partido por bytes conservando el orden
    queue.dart              QueuedJob, SyncStatus
    model.dart              lo que cruza la frontera
    ports.dart              SyncTransport, JobStore, LocalStore,
                            Connectivity, Realtime, Archive, Crypto, Snapshot
    errors.dart             LocalOnlyViolationError y compañía
    adapter.dart            SyncTableAdapter
    uuid.dart               UUID v7, en 30 líneas y sin dependencia
  src/adapters/             el 10% que toca el mundo
    bff_transport.dart      HTTP contra bff-colportores
    backup_codec.dart       gzip + SHA-256 + Isolate.run
  src/testing/              un fake por puerto (R-A2)
test/conformidad/           §8 + R-A1/R-A2
```

## Cómo se usa

```dart
final engine = SyncEngine(
  specs: SpecRegistry(specs, allEntities: Tables.all),  // revienta si falta una
  adapters: appSyncAdapters,                            // uno por entidad remota
  transport: FakeSyncTransport(),                       // o BffTransport(...)
  jobs: DriftJobStore(db),
  store: DriftLocalStore(db),
  connectivity: ConnectivityPlusAdapter(),
);

await db.transaction(() async {
  await ventaDao.insert(venta);
  await engine.stageRow(venta, Op.insert);   // critical → dispara el ciclo solo
});

await engine.stage('persona', ...);          // ← LocalOnlyViolationError
```

Y el fake:

```dart
final transport = FakeSyncTransport()
  ..seed('venta', [ventaQueSubioElCeluViejo]);   // lo que ya está en el servidor

transport.failWith(422);        // la próxima llamada rebota como payload → INVALID
transport.offline();            // sin red hasta online()
transport.loseNextResponse();   // el lote se aplica y la respuesta no vuelve
transport.rejectJob(opId, 'PRODUCTO_INEXISTENTE');
```

Lo que el test observa: `batches` (todo intento, incluidos los que fallaron),
`pulls` (con qué watermark se pidió cada uno), `appliedOpIds` y `rowsOf(entity)`.

Por defecto el fake se porta como un backend correcto: deduplica por
`client_op_id`, trata el insert sobre una PK existente como éxito idempotente,
aplica LWW por `sync_version` y sirve el delta por watermark.

## La suite de conformidad, del lado de la app

§8 dice que el paquete **publica** la suite. No alcanza con que el motor esté
bien: hay que verificar que la app lo declaró bien, y un `SyncSpec` mal puesto
es una fuga de datos personales que ningún test de este lado puede atrapar.

En `front-colportores-mobile`, un archivo de test:

```dart
import 'package:sync_engine/conformance.dart';

void main() => runConformanceSuite(ConformanceFixture(
      specs: appSyncSpecs,
      allEntities: appDb.allTables.map((t) => t.actualTableName).toSet(),
      adapters: appSyncAdapters,
      samples: {'venta': [ventaDeEjemplo], ...},
    ));
```

Verifica: que `persona` y `nota` sigan siendo `local`, que `stage()` sobre ellas
lance, que ninguna tabla quedó sin `SyncSpec`, que cada entidad remota tenga su
`SyncTableAdapter`, que el round-trip de cada adaptador sea identidad, la
máquina de estados de §5.1 y el `recover()` sin backup.

[`test/conformidad/suite_de_la_app_test.dart`](test/conformidad/suite_de_la_app_test.dart)
la usa igual que lo hará la app — es la prueba de que corre.

Por eso `package:test` es dependencia de producción del paquete, no de
desarrollo. Es Dart puro: no arrastra nada de Flutter.

## Ciclo de vida

[`test/ciclo_de_vida_test.dart`](test/ciclo_de_vida_test.dart). `flush()` es lo
que la app llama cuando Android le avisa que la manda a segundo plano, así que
si vuelve antes de que el dato salga la promesa no vale nada. **Ese sí andaba**:
espera al ciclo en curso y después manda lo suyo.

Lo que no andaba: después de `dispose()` el motor seguía aceptando `stage()` en
silencio, encolando en una cola que nadie iba a vaciar. Ahora tira `StateError`.
Como `stage()` se llama **dentro de la transacción de la app**, fallar ahí hace
que tampoco se escriba la fila de negocio — y es lo que se quiere: mejor no
guardar la venta que guardarla y no subirla nunca. Los caminos internos (el
debounce de realtime, un trigger pendiente que se libera) no tiran: simplemente
no hacen nada.

## Dos cosas al mismo tiempo

[`test/concurrencia_test.dart`](test/concurrencia_test.dart). El colportor toca
"hacer backup" mientras corre el del cierre de jornada; vuelve la red justo
mientras el wizard de recuperación reconcilia. Nada de eso es raro: los triggers
de §5.2 son automáticos y el usuario aprieta botones cuando quiere.

**Dos `backupNow()` a la vez bifurcaban la cadena.** Los dos leían la misma
punta y subían con el mismo padre. Un fork deja la cadena entera inservible
—`buildChain` no puede saber cuál rama es la buena— así que un toque de más al
botón inutilizaba todos los backups del colportor. Ahora `BackupService`
serializa: un backup por vez.

**`recover()` no tomaba el candado del ciclo.** Un trigger de conectividad
durante la fase 3 arrancaba un pull en paralelo sobre los mismos scopes. Ahora
toma el mismo candado que los ciclos.

**Y eso destapó un tercero**: un trigger automático que se saltea porque hay algo
corriendo se perdía. Justo el de conectividad, que es cuando más se quiere
sincronizar, y el próximo puede tardar horas. Ahora queda anotado y corre apenas
se libera el candado.

## El motor contra un servidor que se porta mal

[`test/pull_defensivo_test.dart`](test/pull_defensivo_test.dart). Dos cosas que
no había probado y las dos estaban rotas:

**Un `has_more` que nunca baja colgaba la app.** `has_more` lo manda el BFF; si
tiene un bug y lo deja en `true` sin avanzar el watermark, el cliente que le cree
pide la misma página para siempre. Ahora, si el watermark no avanzó, el motor
corta: la próxima request sería idéntica a la anterior.

**`recover()` no era idempotente.** Si la red se cortaba en la fase 3, el wizard
mostraba el error y el botón "reintentar" volvía a restaurar el backup — que en
un Drift real **pisa la DB** y se lleva puesto el replay y la reconciliación que
sí habían terminado. Ahora la fase 1 deja una marca en la propia DB local, así
que un reintento retoma desde la reconciliación aunque la app se haya cerrado en
el medio. El reporte sigue diciendo de cuándo son los datos, porque la fecha
sale de esa marca.

## Lo que quedó en vuelo cuando la app se muere

Un job pasa a `IN_FLIGHT` mientras un ciclo lo tiene en la mano. Si el proceso
muere ahí —Android matando la app para liberar memoria, la batería, un bug del
adaptador— queda así en `sync_queue`, y `claimPending` solo mira los `PENDING`.
**Nadie lo reclamaba: la venta no subía nunca más.**

En un celular de 5 años (RA-PO01) que Android mata de rutina, eso no es un caso
raro. [`test/reinicio_test.dart`](test/reinicio_test.dart) lo demuestra por tres
caminos y verifica el arreglo:

- `JobStorePort.reclaimInFlight()`, que el motor llama una vez por arranque
  antes del primer ciclo. Es seguro reenviar: el `client_op_id` hace que un job
  ya aplicado vuelva `duplicate` (§5.3), y hay un test de exactamente ese caso.
- Y dentro de un mismo ciclo, una guarda: si el push revienta de una forma que
  el código no previó, lo que quedó sin resolver vuelve a `PENDING` antes de
  propagar el error.

Es el hallazgo más serio de todos los que salieron: los otros costaban datos o
milisegundos, este perdía ventas.

## Presupuesto de datos y de memoria

[`test/presupuesto_test.dart`](test/presupuesto_test.dart) mide RR-02 (< 1 MB
por sync) y RA-PO01 (celulares de 5+ años) con cifras realistas, e imprime los
números:

| Escenario | Resultado |
|---|---|
| Una jornada: 120 visitas + 20 ventas | 36,6 KB |
| 7 días sin conexión: 980 registros | 0,25 MB en 2 lotes |
| Backup de una temporada: 15.000 filas, 2,5 MB | **92 KB** (28× menos), 93 ms |

Los dos requisitos se cumplen con margen. El backup de una temporada entera
comprimido entra en 92 KB, así que el incremental del cierre de jornada es
ruido en el plan de datos del colportor.

**Y encontró un desperdicio.** Una jornada eran **21 requests HTTP**: la
escritura crítica de §5.2 disparaba un ciclo por venta, y una venta con tres
items son cuatro escrituras críticas. Ahora hay una ventana de coalescencia de
2 s, igual que la de realtime: una ráfaga es un push. Dos segundos no tocan la
garantía —lo crítico es no esperar al próximo trigger, no salir en el mismo
milisegundo— y en la calle, donde las ventas están separadas por horas, cada una
sigue saliendo sola. `engine.flush()` la saltea cuando no se puede esperar: al
pasar la app a segundo plano, al cerrar la jornada.

También quedó medido, sin arreglar, el costo de no compactar la outbox: editar
la misma fila 51 veces manda 51 jobs, **51× más bytes que mandar solo el
último**. Compactar cambia lo que el servidor ve, así que es una decisión del
contrato y no del motor.

## Dependencias entre entidades — un agujero abierto

§2 declara `venta` y `venta_item` como dos entidades `push` separadas, pero el
contrato v0.9.2 no dice nada sobre qué pasa cuando una depende de la otra.
[`test/dependencias_test.dart`](test/dependencias_test.dart) documenta el
comportamiento actual, incluido el caso malo.

**Lo que sí está garantizado**: el orden de creación se respeta siempre, también
a través de lotes partidos, así que un item nunca viaja antes que su venta. Y
una falla transitoria devuelve el ciclo entero a `PENDING`: una caída de red no
separa una venta de sus items.

**El agujero**: si el backend rechaza la venta con `422` y el item viene en el
mismo lote sin nada de malo, la venta queda `INVALID` y **el item entra**. El
servidor termina con un `venta_item` cuya `venta` no existe. Si el colportor
corrige la venta y la reencola, se arregla; si la descarta, el item queda
huérfano para siempre.

Tres salidas posibles, en orden de costo:

1. **El backend rechaza el item también**, por FK. El motor ya lo maneja: los
   dos jobs quedan `INVALID` juntos y visibles. Cuesta cero del lado del motor
   y es probablemente lo que ya va a pasar con las FK de Postgres — **vale la
   pena confirmarlo antes de hacer nada más**.
2. **Un `dependsOn` en `SyncSpec`**: al invalidar un job, se invalidan los
   posteriores de las entidades que dependen de él. Es explícito y testeable,
   pero agrega API al contrato.
3. **Agrupar por transacción**: `venta` + `venta_item` viajan como una unidad
   que el backend acepta o rechaza entera. Es lo más correcto y lo más caro,
   y toca el formato de cable.

No elegí ninguna: cambia el contrato, y §9 dice que eso requiere acuerdo de las
dos partes.

## Escala

[`test/escala_test.dart`](test/escala_test.dart) corre con los números de una
semana en modo avión con uso diario: 20.000 jobs encolados, subidos en 40 lotes,
todos `DONE`, cero duplicados. Hoy tarda ~240 ms.

Lo escribí porque lo que rompe RR-02 no suele ser la red: es un algoritmo
cuadrático que con 20 jobs no se nota. **Y había tres.** Antes de arreglarlos,
20.000 jobs tardaban 6,3 segundos:

| Causa | Arreglo |
|---|---|
| El motor contaba la cola entera en **cada** `stage()`, aunque nadie escuchara `status` | No emite si `_status` no tiene oyentes. Contra Drift eran 20.000 `COUNT` sobre una tabla que crece |
| Correspondencia `client_op_id` → `jobId` por búsqueda lineal, una por resultado | Un mapa, una vez por ciclo |
| `InMemoryJobStore` guardaba una lista: cada `byId` la recorría entera | Indexado por id, con contadores incrementales para `status()` |

El tercero es del fake, pero importa igual: es contra lo que la app se desarrolla
entre hitos, y también sobre lo que corren el caos y la escala. Un fake lento
esconde el comportamiento real y hace que nadie quiera correr los tests.

La cota del test quedó en 4 s: un cuadrático se pasa por órdenes de magnitud, no
por un 20%, así que si falla es complejidad y no una máquina lenta.

## El archivo remoto (Drive)

`DriveArchive` implementa `ArchivePort` sobre HTTP: contra `drive-mock` en
desarrollo, contra Drive en producción cambiando la `baseUrl`. **El OAuth queda
afuera**, igual que en `BffTransport`: la app le pasa una función `token()`, así
que este archivo no depende de `google_sign_in` y se prueba sin una cuenta de
Google.

```bash
cd prototipo-sync && docker compose up -d drive-mock
DRIVE_URL=http://localhost:8090 dart test test/drive_archive_test.dart
```

**Los metadatos de la cadena van en `appProperties`, no en el nombre del
archivo.** El padre, el watermark y el hash del contenido son lo que hace que
`verifyChain()` pueda decir si la cadena está sana; el nombre no lo indexa nadie
y un rename la rompería entera.

**El `contentHash` lo calcula el cliente sobre lo que sube**, y viaja como
metadato. Que no lo calcule el servidor es justamente lo que le da sentido a
`verifyChain()`: si el archivo remoto devuelve bytes distintos de los que se
subieron, el hash guardado no coincide con el de lo que bajó. Tiene que ser el
**mismo** digest que el `CryptoPort` en juego, o la cadena da rota siempre.

**Un archivo sin metadatos no entra en la cadena.** Uno suelto en el
`appDataFolder` —de una versión vieja, o a medio subir— se ignora en `list()`.
Si se colara como eslabón, `verifyChain()` daría cadena rota para siempre y el
colportor no podría restaurar nada. Hay un test que sube uno crudo y verifica
que no aparece.

Esto importa más de lo que parece: `persona`, `nota` y `espacio_persona` son
`local` y **nunca** salen por sync. El backup E2E es lo único que separa al
colportor de perder su lista de clientes junto con el celular.

## Tests de contrato de los puertos

El motor se verificó entero contra los fakes de `lib/src/testing/`. Eso deja un
agujero: nada garantiza que el `DriftJobStore` de verdad se comporte como el
`InMemoryJobStore` con el que se probó cada invariante. Si el de Drift devuelve
los `PENDING` en otro orden, o deja salir un `INVALID` en el claim, el motor
hace cosas que ningún test vio.

[`lib/port_contracts.dart`](lib/port_contracts.dart) publica la definición
ejecutable de cada puerto:

```dart
import 'package:sync_engine/port_contracts.dart';

void main() {
  runJobStoreContract('DriftJobStore', () => DriftJobStore(dbEnMemoria()));
  runLocalStoreContract('DriftLocalStore', () => DriftLocalStore(dbEnMemoria()));
  runArchiveContract('DriveAdapter', () => DriveAdapter(cuentaDePrueba));
}
```

Los fakes las pasan ([`test/port_contracts_test.dart`](test/port_contracts_test.dart)),
que es la prueba de que la suite corre. Los adaptadores que necesitan dispositivo
—Drive, keystore— corren estas mismas suites en la mini app de harness, en
I1–I4: es exactamente el contenido que le falta a ese harness.

Una de esas pruebas vale la pena mirarla ahora: **`applyDelta` con un delta
vacío tiene que guardar el watermark igual**. La fase 1 de §7 lo usa para dejar
puesto el watermark del backup sin escribir ninguna fila; una implementación de
Drift que se saltee el guardado cuando no hay filas hace que la reconciliación
arranque desde cero y rebaje todo lo que la DB restaurada ya tenía.

## En el CI

```yaml
- run: dart pub get
  working-directory: packages/sync_engine
- run: dart analyze --fatal-infos
  working-directory: packages/sync_engine
- run: dart test
  working-directory: packages/sync_engine
```

Sin emulador, sin dispositivo, sin backend. Es la garantía §5.9 hecha comando.

## Tests de invariantes bajo caos

[`test/caos_test.dart`](test/caos_test.dart) genera secuencias aleatorias con
semilla fija —escrituras, cortes de red, respuestas perdidas, rechazos del
backend, transacciones locales que fallan— y verifica lo único que no puede
pasar nunca:

1. Ningún job queda colgado: al final está `DONE` o `INVALID`.
2. Cero duplicados: una venta subida N veces es una fila.
3. Nada se pierde: todo job `DONE` está en el servidor.
4. Nada se inventa: en el servidor no hay nada que nadie haya stageado.
5. El watermark nunca retrocede, y ninguna fila se aplica dos veces.

Los tests de ejemplo verifican los casos que alguien pensó; un motor de sync se
rompe en los que no. La semilla es fija, así que un fallo se reproduce.

**Ya encontró uno**: el fake dejaba que un rechazo programado le ganara al cache
de `client_op_id`, produciendo una fila en el servidor con el job en `INVALID`
—un estado que ningún backend con cache de idempotencia puede producir, y que
dejaría al colportor con una venta en la cola de error que en realidad ya cobró.
Importa porque el fake es contra lo que la app se desarrolla entre hitos: un
fake que miente forma código que después falla contra el BFF real.

## La mitad no-nativa del backup

[`CompressingCrypto`](lib/src/adapters/backup_codec.dart) deja el adaptador de
plataforma reducido a dos métodos —`encryptBytes` y `decryptBytes`, la llamada a
AES-GCM del crypto del OS—. Todo lo demás ya está hecho y corre en la VM:

```dart
class NativeCrypto extends CompressingCrypto {
  @override
  Future<List<int>> encryptBytes(List<int> plaintext) async { /* AES-GCM */ }
  @override
  Future<List<int>> decryptBytes(List<int> ciphertext) async { /* … */ }
}
```

**Comprime antes de cifrar, y ese orden no es negociable.** Un ciphertext bien
construido es indistinguible de ruido, y el ruido no comprime. La DB de un
colportor son strings repetidos: en el test, un backup de 2000 ventas pasa de
~250 KB a menos de 50 KB. Al revés, el colportor pagaría el backup entero sin
comprimir de su plan de datos.

**El hash es sobre el ciphertext**, así `verifyChain()` verifica la integridad de
la cadena sin descifrar nada y por lo tanto sin la clave del usuario.

**El gzip va a `Isolate.run`** arriba de 64 KB, que es lo que mantiene la UI a
60 fps mientras se arma el backup del cierre de jornada (Apéndice A). Debajo de
ese umbral arrancar el isolate cuesta más que comprimir.

## El formato de cable

§6 dice que el batch va por el BFF, pero el contrato no fija la forma de los
mensajes. La propuesta está en [`docs/formato-de-cable.md`](docs/formato-de-cable.md)
y es lo que implementa `BffTransport`; `bff-colportores/src/sync/` tiene que
hablar eso. Como §4 pone las dos puntas del mismo lado, es una decisión de una
sola persona — pero conviene que entre al contrato en v1.0 antes de que haya dos
implementaciones que se crean compatibles.

`BffTransport` usa `package:http`, que es Dart puro, así que se testea con
`MockClient` sin levantar el BFF — incluido un test de integración que hace pasar
al motor entero por HTTP real serializado.

## Decisiones que conviene mirar antes de congelar v1.0

**`TransportFailure` lleva una `FailureKind`, no un status.** El núcleo no sabe
que existe HTTP; la traducción vive en `kindForStatus()`, compartida por el fake
y por el futuro `BffTransport` para que no puedan discrepar. Clasificar es lo
único que decide entre `PENDING` e `INVALID` (§5.1), así que no puede haber dos
tablas.

**El delta se sirve por watermark, no por cola.** Pedir dos veces desde el mismo
punto devuelve dos veces lo mismo. Sin eso no se puede probar que un fallo al
aplicar la transacción local deja el watermark quieto.

**`conflict` es un outcome, no una falla.** Un 409 vuelve con `serverRow`, así
el motor resuelve el LWW sin un pull extra, y el job no toca `INVALID`.

**`duplicate` es éxito.** Es lo que sostiene el replay de §7 cuando el backup es
más viejo que el TTL de 24 h del cache de `client_op_id`.

### Ocho cosas que el contrato todavía no fija

Todas están marcadas en el código. Son las que conviene cerrar antes de
congelar v1.0.

1. **El `401` no está en la tabla de §5.1.** Acá quedó como `transient`, con el
   argumento de que el refresh del JWT es de la app (§10): el job espera y sube
   al próximo trigger con el token nuevo. Si tiene que ser otra cosa, cambia
   `kindForStatus()`.
2. **El nombre del campo PK en el payload.** El fake usa `id`, configurable. §7
   depende de que la PK sea el UUID v7 del dispositivo, así que el nombre
   tendría que ser parte del `SyncTableAdapter`.
3. **Qué responde el BFF cuando un lote se pasa de 1 MB.** Hay `buildBatches()`
   para armar lotes bajo el tope; si además hay un status de rechazo, va a
   `kindForStatus()`.
4. **Una falla de payload de la llamada entera** (no de un job). Acá manda a
   `INVALID` a todos los jobs de ese lote: reintentarlo tal cual daría el mismo
   error para siempre. Discutible — puede convenir partir el lote para aislar
   al culpable.
5. **`stage()` sobre una entidad `pull`.** §2 dice que la app nunca escribe esas
   tablas pero no nombra un error. Agregué `ReadOnlyEntityError`, simétrico a
   `LocalOnlyViolationError`.
6. **Si el ahorro de datos frena también el pull de realtime.** §3 dice que
   "solo afecta batch", y el pull que dispara un evento *es* un delta batch por
   REST, así que acá lo frena. El cambio no se pierde: entra en el próximo
   ciclo. Si la idea era que realtime pase igual, es una línea.
7. **Qué pasa con las dependencias entre entidades** cuando una queda
   `INVALID` y la otra no. Ver arriba; hay un test que lo demuestra.
8. **Cuántos watermarks hay.** §7 los nombra en singular, pero la fase 3
   (entidades `push`/`alsoPull` desde el backup) y la fase 4 (catálogos desde
   cero) parten de puntos distintos, así que el watermark se guarda por *scope*
   (`replica`, `mirror`). Si es uno solo, se simplifica.
