# Formato de cable entre el motor y Supabase

**Estado**: es el formato que fija el contrato §6.1 (0.9.10). Desde ADR-013
(docs-organizacion#22) no hay BFF en la Fase 1: el motor llama directo a las
funciones de entrada del sync en `public` de Supabase, `sync_push` y
`sync_pull` (backend-supabase 0025, #53), que reciben **este mismo JSON**.

Lo implementan [`core/wire.dart`](../lib/src/core/wire.dart) (el mensaje) y
[`adapters/supabase_rpc_transport.dart`](../lib/src/adapters/supabase_rpc_transport.dart)
(el HTTP). Del lado de la base, `sync.validar_sobre()` sigue a
`envelopeFromJson()` regla por regla.

[`adapters/bff_transport.dart`](../lib/src/adapters/bff_transport.dart) se
conserva para el BFF diferido: mismo mensaje, pero el pull va por `GET` con
query y los errores se clasifican solo por status (ver [el BFF
diferido](#el-bff-diferido)).

## Reglas generales

- `POST <proyecto>/rest/v1/rpc/<función>`, JSON, UTF-8.
- Headers: `apikey: <anon key>` siempre, y `Authorization: Bearer <jwt>` con el
  JWT del colportor cuando hay sesión (sin sesión no va `Authorization`). Las
  funciones son `security invoker`: corren con la RLS y el `auth.uid()` del
  colportor.
- El cuerpo va envuelto en `{"p_body": …}`, que es el único argumento de las
  dos funciones. Lo que va adentro es lo que arma el codec.
- Los decimales viajan como **string** (`"1200.00"`), nunca como número, **en
  las dos direcciones**. Un `double` pierde precisión en montos, y del lado del
  servidor `to_jsonb(fila)` convierte un `numeric(10,2)` en número JSON: `42.50`
  sale como `42.5` y `jsonDecode` lo parsea como `double`. Vale también para el
  `server_row` de un `conflict`, que es una fila como cualquier otra.
- Las fechas, ISO-8601 en UTC con `Z`.
- El `watermark` es un **string opaco** para el cliente: se guarda tal cual y
  se devuelve tal cual. Hoy es el `jsonb` de `sync.pull()` serializado, pero eso
  es del servidor. Un `watermark` que no es string es una respuesta ilegible
  (`transient`), no un cursor.
- Toda request lleva el **sobre** de §5.3 en `device`: `device_id`,
  `app_version` y `schema_version`. Es el mismo en el push y en el pull, y lo
  arma el mismo codec.

## El sobre (§5.3)

```json
{ "device_id": "018f2c4e-6b7d-7a11-9f3c-8e2d5b6a7c90",
  "app_version": "1.4.2",
  "schema_version": 1 }
```

| Campo | Qué es |
|---|---|
| `device_id` | UUID de la **instalación**, no del colportor ni del hardware. Lo genera el dispositivo en el primer arranque y lo guarda en `flutter_secure_storage`. Existe antes del login, que es lo que permite encolar sin sesión; una reinstalación estrena uno, que es lo correcto porque la réplica también arranca de cero |
| `app_version` | Solo telemetría. No decide nada: si falta, el ciclo sigue igual. Cortar una sync por una métrica sería cambiar ventas por un dato |
| `schema_version` | La del **formato de cable**, no la de la app. Sube solo ante un cambio incompatible (§9). La base la compara contra la mínima que entiende (hoy 1) |

Sin el sobre no existe "el dispositivo": dos teléfonos del mismo colportor son
indistinguibles para el servidor, `sync.log` no puede separarlos, y no hay forma
de cerrar la sesión de uno perdido sin cerrar todas.

## Push: `POST /rest/v1/rpc/sync_push`

```json
{ "p_body": {
  "device": { "device_id": "018f…", "app_version": "1.4.2", "schema_version": 1 },
  "jobs": [
    {
      "client_op_id": "018f2c4e-6b7d-7a11-9f3c-8e2d5b6a7c90",
      "entity": "venta",
      "op": "insert",
      "sync_version": null,
      "payload": { "id": "018f…", "total": "1200.00" }
    }
  ]
} }
```

`op` es `insert` | `update` | `delete`. `sync_version` es `null` en los insert y
la versión esperada en los demás (§5.4).

Topes: **500 jobs y 1 MB** por lote. El MB se mide sobre `jobs` como texto de
`jsonb`, que pone un espacio después de cada `:` y cada `,`, así que pesa un poco
más que el JSON compacto con el que `buildBatches` arma los lotes. Un lote al
borde puede volver con `CS003` (ver [rechazos del lote](#rechazos-del-lote-entero)).

**200** — siempre que el lote entró a la función, aunque haya jobs rechazados: la
aceptación es por job.

```json
{
  "server_time": "2026-11-13T08:00:00.000Z",
  "results": [
    { "client_op_id": "…", "outcome": "accepted",  "sync_version": 1 },
    { "client_op_id": "…", "outcome": "duplicate" },
    { "client_op_id": "…", "outcome": "conflict",  "sync_version": 3,
      "server_row": { "id": "…", "total": "9999.00", "sync_version": 3 } },
    { "client_op_id": "…", "outcome": "conflict", "code": "23505",
      "constraint": "ubicacion_direccion_unica", "message": "Ya hay otra ubicación en …" },
    { "client_op_id": "…", "outcome": "conflict",
      "code": "ESPERA_ALTA_EN_CONFLICTO", "depends_on": "018f…", "message": "…" },
    { "client_op_id": "…", "outcome": "invalid",
      "code": "23503", "message": "…" }
  ]
}
```

La tabla es la de §6.1. `constraint` y `depends_on` llegan al motor en
`JobResult.constraint` y `JobResult.dependsOn`.

| `outcome` | `code` | Qué hace el motor |
|---|---|---|
| `accepted` | — | job → `DONE` |
| `duplicate` | — | job → `DONE`. **Es éxito**: mismo `client_op_id`, o alta sobre una PK que ya existe (§7) |
| `conflict` | — (con `server_row`) | LWW con `server_row`, después → `DONE`. No es culpa del colportor |
| `conflict` | `23505` con `constraint` `ubicacion_direccion_unica` | Misma dirección a menos de 100 m (§2.2). **Sin** `server_row`: la fila queda en el teléfono y la app la resuelve en la vista 10 |
| `conflict` | `ESPERA_ALTA_EN_CONFLICTO` (con `depends_on`) | Cuelga de un alta que volvió en conflicto. **En espera**: se reintenta cuando se resuelve el alta |
| `invalid` | `CG001`, `UB001`, `UB002` | job → `INVALID`, con aviso propio en la app |
| `invalid` | `42501`, `FILA_INEXISTENTE`, clase `22` o `23`, `ENTIDAD_DESCONOCIDA`, `ENTIDAD_DE_SOLO_LECTURA`, `OP_INVALIDA`, `OP_ID_REQUERIDO`, `PAYLOAD_VACIO`, `PK_FALTANTE` | job → `INVALID`, con el `code` visible en la UI |

> **Pendiente en el núcleo (#178)**: las dos filas de `conflict` sin
> `server_row` todavía terminan en `DONE`, como el conflicto de siempre. El
> estado «en espera» de §5.1 no existe en `JobState`. Hasta que entre, el
> transporte las trae bien pero el motor no las trata como dice la tabla.

`server_row` en el conflicto de LWW no es opcional: sin ella el motor tiene que
hacer un pull extra solo para resolver un LWW.

**Un job con el payload roto vuelve `invalid`, nunca `5xx`.** Una fecha que no
es fecha o una FK que no existe es un dato malo, no una falla del servidor. Si
saliera como `5xx`, el motor lo clasificaría como transitorio y lo reintentaría
para siempre: un solo job venenoso bloquearía la cola del colportor y ninguna
venta volvería a subir. El `code` en ese caso es el SQLSTATE.

## Pull: `POST /rest/v1/rpc/sync_pull`

Pasó de `GET` con query a `POST` con cuerpo, con el sobre en `device` como en el
push:

```json
{ "p_body": {
  "device": { "device_id": "018f…", "app_version": "1.4.2", "schema_version": 1 },
  "entities": ["venta", "producto"],
  "watermark": "…",
  "limit": 500
} }
```

`entities` es un **array**, no una lista con comas. `watermark` y `limit` son
opcionales y el codec los omite cuando son nulos: sin `watermark` es una réplica
desde cero, y sin `limit` decide el servidor. El alcance no se manda: la ciudad
sale de la zona del colportor (§2.1). **200**:

```json
{
  "server_time": "2026-11-13T08:00:00.000Z",
  "watermark": "{\"venta\": {\"sv\": 12, …}}",
  "has_more": false,
  "rows": {
    "producto": [ { "id": "…", "nombre": "El Camino a Cristo", "sync_version": 4 } ]
  }
}
```

`watermark` es el string que va tal cual en el pedido siguiente. Si no viene,
el motor conserva el que tenía: inventar uno sería adelantar el cursor sin
datos. Una entidad **ausente** de `rows` significa "sin cambios". El motor no borra
nada por ausencia. Si `has_more` es `true`, vuelve a pedir con el `watermark`
nuevo antes de considerar la sync completa.

## Rechazos del lote entero

PostgREST devuelve todo error de la base con el SQLSTATE en `code`:

```json
{ "code": "CS002", "message": "…", "details": null, "hint": null }
```

y **todo SQLSTATE propio sale como `400`**. El status solo no alcanza para
clasificar (`CS001` y `CS002` comparten `400` y uno es payload y el otro no), así
que el transporte decide **primero por `code`** (`kindForRpcError`) y, si el
código no está en la tabla, por el status (`kindForStatus`, §5.1):

| `code` | Status | Cuándo | `FailureKind` | Efecto |
|---|---|---|---|---|
| `CS001` | `400` | Sobre mal formado: no es objeto, `device_id` no es UUID o `schema_version` no es entero | `payload` | Los jobs del lote → `INVALID` |
| `CS002` | `400` | Sin sobre, o `schema_version` menor a la mínima | `transient` | → `PENDING`; suben cuando se actualiza la app. La UI lo distingue de «sin red» por el `code` |
| `CS003` | `400` | Más de 500 jobs o más de 1 MB | — | El transporte parte el lote por la mitad, en orden, y sube cada parte. Un lote de un solo job que igual pasa el tope vuelve como resultado `invalid` con `code` `CS003`, y el resto sigue |
| `42501` | `401`/`403` | Sin sesión | `transient` | → `PENDING`; espera el refresh del token (§10) |
| `22023` | `400` | `jobs`, `entities`, `watermark` o `limit` con otra forma | `payload` | Los jobs del lote → `INVALID` |

El resto cae a la clasificación por status:

| Status | `FailureKind` | Efecto |
|---|---|---|
| otro `400`, `403`, `422` | `payload` | Los jobs del lote → `INVALID` |
| `409` | `conflict` | LWW |
| `429` | `transient` | Respeta `Retry-After` (segundos) |
| `401` (`PGRST301`, JWT vencido) | `transient` | El refresh es de la app (§10). El motor además anota **desde cuándo** viene fallando (`SyncStatus.unauthorizedSince`), para que un refresh roto no reintente en silencio |
| `404` (`PGRST202`, la función no existe) | `transient` | La base todavía no tiene la migración: reintenta |
| `5xx`, timeout, sin red | `transient` | → `PENDING`, reintenta al próximo trigger |

Una respuesta que no se puede parsear —que no es JSON, o es JSON con otra forma,
como un `watermark` que no es string— se trata como `transient`
(`RESPUESTA_ILEGIBLE`): es un bug del servidor, y mandar a `INVALID` un job válido
porque la respuesta vino rota sería peor que reintentarlo.

**Un job con el payload roto vuelve `invalid` en el 200, nunca como error de la
llamada.** Si saliera como `5xx`, el motor lo clasificaría como transitorio y lo
reintentaría para siempre: un solo job venenoso bloquearía la cola del colportor.

### Por qué `CS003` lo resuelve el transporte

Partir el lote dentro del adaptador deja intactos el núcleo, la cola y
`buildBatches`: para el motor, el lote volvió con un resultado por job, como
siempre. Las partes suben en orden de creación (§5.5). Si una parte falla por
otra cosa, la falla sale entera aunque las anteriores hayan entrado: el motor
devuelve el lote a `PENDING` y, al reintentarlo, lo que ya entró vuelve
`duplicate` por su `client_op_id`.

Partir puede separar un alta en conflicto de lo que cuelga de ella. El servidor
solo pone **en espera** lo que cuelga de un alta del **mismo** lote (0017 §5):
si quedan en partes distintas, lo que cuelga vuelve `invalid` (`23503`,
`42501` o `FILA_INEXISTENTE`). Partir por la mitad mantiene juntos los jobs
vecinos, así que pasa solo en el corte.

### Por qué `CS002` es transitorio y no un error de payload

Una app vieja no manda datos malos: manda datos buenos en un formato que el
servidor ya no interpreta. Si `CS002` fuera `payload`, los jobs irían a
`INVALID` —a la cola de error, sin reintento automático— y el colportor vería
sus propias ventas marcadas como un error suyo. Al actualizar la app no
subirían solas: habría que apretar "reintentar" una por una.

Como `transient`, quedan en `PENDING` y el primer ciclo después de actualizar
las sube. Lo que sí necesita la UI es distinguirlo de "sin red", y para eso está
el `code`: la pantalla puede decir "actualizá la app" en vez de "esperando
conexión".

Un sobre **ausente** se trata igual que uno viejo: un cliente que no lo manda es
anterior a v1.0 del cable. Un sobre **presente y mal formado** sí es `CS001`:
eso no es una app vieja, es un cliente que no cumple.

## El BFF diferido

`BffTransport` habla el formato anterior contra `bff-colportores`, que ADR-013
difiere a una implementación futura: `POST /sync/push` con el cuerpo sin
envolver, `GET /sync/pull?entities=venta,producto&watermark=…&limit=500&device_id=…&app_version=…&schema_version=…`,
y los errores clasificados solo por status, con `426` (`SCHEMA_VERSION_VIEJA`)
como transitorio en lugar de `CS002`. El mensaje sale del mismo codec, así que
si el BFF vuelve, vuelve con el mismo JSON.
