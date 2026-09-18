# Propuesta de cambios para congelar el contrato en v1.0

**Para**: `osorio-cristian--wt` · **De**: `BrunoFCapri` · **Fecha**: 28/08/2026
**Contra**: Contrato del motor de sincronización v0.9.2
**Deadline**: cierre del Sprint 2 — **11/09/2026**, en 14 días

§9 dice que todo cambio al contrato va en un PR que actualice el documento **y**
la suite de conformidad. Esto es el borrador de ese PR: sale de implementar el
motor completo contra v0.9.2, así que cada punto tiene código y un test detrás.

El motor está en `packages/sync_engine`: 228 tests, `dart test` sin emulador ni
backend. Lo que falta son los adaptadores de plataforma (§11, I1–I4).

---

## A. Cambios aditivos — no rompen el contrato (§9: minor)

Van al changelog, no necesitan acuerdo. Los listo para que no aparezcan de
sorpresa en el review.

| Agregado | Por qué |
|---|---|
| `engine.errorQueue()` | §3 tiene `requeue(jobId)` pero nada que devuelva jobIds. Sin esto, la pantalla de cola de error de I3 es imposible sin que la app consulte `sync_queue` a mano y quede atada al esquema interno del motor |
| `engine.stageRow(fila, op)` | La forma tipada de `stage`, con el `SyncTableAdapter` como única fuente de entidad, payload y `sync_version`. Las entidades `local` no tienen adaptador, así que no existe el camino tipado para filtrar una persona |
| `engine.flush()` | Dispara ya lo que espera la ventana de coalescencia y espera a que termine. La app la llama al pasar a segundo plano |
| `JobStorePort.reclaimInFlight()` | Ver punto B7. Es obligatorio para el `DriftJobStore` |
| `JobStorePort.listInvalid()` | Lo que alimenta `errorQueue()` |
| `SyncEngine.criticalDebounce` (2 s) y `realtimeDebounce` (300 ms) | Ver B8 |

`stage()` cambió: el `client_op_id` ahora es opcional y lo genera el motor, como
lo muestra §3. Es un detalle de idempotencia del transporte, no algo que la capa
de datos tenga que acertar.

---

## B. Lo que necesita acuerdo antes del 11/09

Ocho puntos. Todos están decididos de alguna manera en el código —había que
elegir para poder implementar— y todos son de una línea si la decisión es otra.

### B1. El `401` no está en la tabla de §5.1 ✅

**Decidí**: `transient`. El refresh del JWT es de la app (§10), así que el job
espera y sube al próximo trigger con el token nuevo. La clasificación no se
mueve: la sesión es nuestra y el dato es del colportor, así que mandar a
`INVALID` una venta buena porque venció un token la esconde detrás de un
"reintentar" que el colportor no tiene por qué entender.

**El riesgo que anotaba —"con un refresh roto, los jobs reintentan para siempre
en vez de avisar"— ya no queda abierto** (31/08, junto con la auth real de H2).
No se arregla cambiando la clasificación sino haciendo que el reintento deje de
ser silencioso: `SyncStatus.unauthorizedSince` dice **desde cuándo** el backend
contesta `401`, y con eso la app puede decir "volvé a iniciar sesión" en vez de
mostrar "sincronizando" toda la jornada mientras la cola no baja.

Lo limpia solo un ciclo que funcionó: quedarse sin red no cuenta, porque no
saber si la sesión anda no es lo mismo que saber que anda, y si la falta de
cobertura lo limpiara el aviso aparecería y desaparecería todo el día.
**Dónde**: `kindForStatus()`, `SyncEngine._anotarSesion()`, `test/sesion_test.dart`.

### B2. El nombre del campo PK en el payload

§7 apoya el replay idempotente en que la PK sea un UUID v7 del dispositivo, pero
el contrato no nombra el campo. **Propongo** que sea parte del
`SyncTableAdapter` (ya tiene `pkOf`), y que el formato de cable lo fije como
`id`.

### B3. El tope del lote

§5.5 dice "≤ 1 MB típico" pero no qué responde el BFF si se pasa. **Implementé**
`buildBatches()`, que arma lotes bajo el tope, así que en la práctica no debería
pasar. Si igual hay un status de rechazo, va a `kindForStatus()`.

### B4. Una falla de payload de la llamada entera

Un `422` de un job puntual vuelve en `results`. ¿Y un `422` del request entero?
**Decidí**: todos los jobs de ese lote → `INVALID`, porque reintentarlo igual
daría el mismo error para siempre. **Alternativa**: partir el lote para aislar al
culpable. Cuesta más y solo vale si el BFF puede fallar así.

### B5. `stage()` sobre una entidad `pull`

§2 dice que la app nunca escribe esas tablas pero no nombra un error. **Agregué**
`ReadOnlyEntityError`, simétrico a `LocalOnlyViolationError`.

### B6. Cuántos watermarks hay

§7 los nombra en singular, pero la fase 3 (entidades `push`/`alsoPull` desde el
backup) y la fase 4 (catálogos desde cero) arrancan de puntos distintos.
**Implementé** un watermark por *scope*: `replica`, `mirror` y `recovery`. Si va
a ser uno solo, se simplifica.

### B7. Qué pasa con lo que quedó `IN_FLIGHT` cuando muere el proceso

**No está en el contrato y es el hallazgo más serio.** Un job pasa a `IN_FLIGHT`
mientras un ciclo lo tiene en la mano; si Android mata la app ahí, queda así en
`sync_queue` y `claimPending` no lo mira: **la venta no sube nunca más**. En un
celular de 5 años (RA-PO01) eso pasa seguido.

**Propongo** agregarlo a §5.1 como garantía: *"al arrancar, todo job `IN_FLIGHT`
vuelve a `PENDING`. Es seguro porque el `client_op_id` hace que un job ya
aplicado vuelva `duplicate`."* Ya está implementado y testeado, y es requisito
del `DriftJobStore`.

### B8. Coalescencia de los triggers

§5.2 dice que una escritura crítica dispara un ciclo. Una venta con tres items
son cuatro escrituras críticas: medido, una jornada eran **21 requests HTTP**.
**Implementé** una ventana de 2 s. No toca la garantía —lo crítico es no esperar
al próximo trigger, no salir en el mismo milisegundo— y `flush()` la saltea.
Mismo caso en realtime: 50 eventos de una lista de precios eran 18 pulls, ahora
uno.

**Propongo** que §5.2 diga que los triggers se coalescen en una ventana corta.

---

## C. El agujero de dependencias entre entidades

`venta` y `venta_item` son dos entidades `push` separadas y el contrato no dice
qué pasa cuando una depende de la otra.

**Lo que está garantizado** (con test): el orden de creación se respeta siempre,
también a través de lotes partidos, y una falla transitoria devuelve el ciclo
entero a `PENDING`.

**El agujero**: si el backend rechaza la venta con `422` y el item viene en el
mismo lote sin nada de malo, la venta queda `INVALID` y el item **entra**. Queda
un `venta_item` cuya `venta` no existe.

Tres salidas, en orden de costo:

1. **El backend lo rechaza por FK.** El motor ya lo maneja: los dos quedan
   `INVALID` juntos y visibles. Cuesta cero. **Mi apuesta es que ya está
   resuelto por las FK de Postgres y que la conversación termina en confirmarlo
   mirando el esquema.**
2. **Un `dependsOn` en `SyncSpec`**: al invalidar un job se invalidan los
   posteriores de las entidades que dependen de él.
3. **Agrupar por transacción**: `venta` + items viajan como una unidad que el
   backend acepta o rechaza entera. Lo más correcto y lo más caro; toca el
   formato de cable.

---

## D. El formato de cable

§6 dice que el batch va por el BFF pero no fija la forma de los mensajes. La
propuesta está en [`formato-de-cable.md`](./formato-de-cable.md) y es lo que
implementa `BffTransport`. **Conviene cerrarlo antes que nada**: es lo único de
esta lista que, si queda abierto, bloquea I1.

---

## E. Lo que este trabajo agrega a §8

La suite de conformidad ahora se publica como
`package:sync_engine/conformance.dart` y corre en el CI de la app con cinco
líneas. Además hay `package:sync_engine/port_contracts.dart`: la definición
ejecutable de cada puerto, que el `DriftJobStore`, el `DriftLocalStore` y el
`DriveAdapter` tienen que pasar. Los adaptadores que necesitan dispositivo las
corren en el harness de I1–I4, así nadie improvisa qué verificar.
