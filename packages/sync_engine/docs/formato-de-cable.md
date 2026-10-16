# Formato de cable entre el motor y el BFF

**Estado**: propuesta. No está en el contrato v0.9.2 — §6 dice que el batch va
por `bff-colportores`, pero no fija la forma de los mensajes. Como §4 pone las
rutas de sync del BFF y el paquete del mismo lado, esto es una decisión de una
sola persona; queda escrito acá para que se pueda discutir y, si sirve, entre al
contrato en v1.0.

Lo implementa [`adapters/bff_transport.dart`](../lib/src/adapters/bff_transport.dart)
y lo consume `bff-colportores/src/sync/`.

## Reglas generales

- JSON, UTF-8. `Authorization: Bearer <jwt>` en toda request.
- Los decimales viajan como **string** (`"1200.00"`), nunca como número, **en
  las dos direcciones**. Un `double` pierde precisión en montos, y del lado del
  servidor `to_jsonb(fila)` convierte un `numeric(10,2)` en número JSON: `42.50`
  sale como `42.5` y `jsonDecode` lo parsea como `double`. Vale también para el
  `server_row` de un `conflict`, que es una fila como cualquier otra.
- Las fechas, ISO-8601 en UTC con `Z`.
- El `watermark` es **opaco** para el cliente: se guarda tal cual y se devuelve
  tal cual. El BFF elige qué mete adentro.
- Toda request lleva el **sobre** de §5.3: `device_id`, `app_version` y
  `schema_version`. Va en el cuerpo del push y en el query del pull —un `GET` no
  tiene cuerpo—, pero es el mismo sobre y lo arma el mismo codec.

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
| `schema_version` | La del **formato de cable**, no la de la app. Sube solo ante un cambio incompatible (§9). El BFF la compara contra la mínima que soporta |

Sin el sobre no existe "el dispositivo": dos teléfonos del mismo colportor son
indistinguibles para el servidor, `sync.log` no puede separarlos, y no hay forma
de cerrar la sesión de uno perdido sin cerrar todas.

## `POST /sync/push`

```json
{
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
}
```

`op` es `insert` | `update` | `delete`. `sync_version` es `null` en los insert y
la versión esperada en los demás (§5.4).

**200** — siempre, aunque haya jobs rechazados: la aceptación es por job.

```json
{
  "server_time": "2026-11-13T08:00:00.000Z",
  "results": [
    { "client_op_id": "…", "outcome": "accepted",  "sync_version": 1 },
    { "client_op_id": "…", "outcome": "duplicate" },
    { "client_op_id": "…", "outcome": "conflict",  "sync_version": 3,
      "server_row": { "id": "…", "total": "9999.00", "sync_version": 3 } },
    { "client_op_id": "…", "outcome": "invalid",
      "code": "PRODUCTO_INEXISTENTE", "message": "pk_producto 812 no existe" }
  ]
}
```

| `outcome` | Qué hace el motor |
|---|---|
| `accepted` | job → `DONE` |
| `duplicate` | job → `DONE`. **Es éxito**: mismo `client_op_id`, o insert sobre una PK que ya existe (§7) |
| `conflict` | LWW con `server_row`, después → `DONE`. No es culpa del colportor |
| `invalid` | job → `INVALID`, con `code` visible en la UI |

`server_row` en un `conflict` no es opcional: sin ella el motor tiene que hacer
un pull extra solo para resolver un LWW.

**Un job con el payload roto vuelve `invalid`, nunca `5xx`.** Una fecha que no
es fecha o una FK que no existe es un dato malo, no una falla del servidor. Si
saliera como `5xx`, el motor lo clasificaría como transitorio y lo reintentaría
para siempre: un solo job venenoso bloquearía la cola del colportor y ninguna
venta volvería a subir. El `code` en ese caso es el SQLSTATE.

## `GET /sync/pull`

```
GET /sync/pull?entities=venta,producto&watermark=…&limit=500
             &device_id=018f…&app_version=1.4.2&schema_version=1
```

`entities` es una lista separada por comas. `watermark` ausente = réplica desde
cero. **200**:

```json
{
  "server_time": "2026-11-13T08:00:00.000Z",
  "watermark": "eyJ0cyI6…",
  "has_more": false,
  "rows": {
    "producto": [ { "id": "…", "nombre": "El Camino a Cristo", "sync_version": 4 } ]
  }
}
```

Una entidad **ausente** de `rows` significa "sin cambios". El motor no borra
nada por ausencia. Si `has_more` es `true`, vuelve a pedir con el `watermark`
nuevo antes de considerar la sync completa.

## Errores

Cuerpo igual en todos: `{ "code": "…", "message": "…" }`. Lo que decide qué hace
el motor es el **status**, según §5.1:

| Status | `FailureKind` | Efecto |
|---|---|---|
| `400`, `403`, `422` | `payload` | Los jobs del lote → `INVALID` |
| `409` | `conflict` | LWW |
| `429` | `transient` | Respeta `Retry-After` |
| `5xx`, timeout, sin red | `transient` | → `PENDING`, reintenta al próximo trigger |
| `401` | `transient` | El refresh es de la app (§10): el job espera y sube con el token nuevo. El motor además anota **desde cuándo** viene fallando (`SyncStatus.unauthorizedSince`), para que un refresh roto no reintente en silencio |
| `503` | `transient` | El BFF no pudo **averiguar** si la sesión vale (el JWKS no contesta y no tiene cache). No es `401` a propósito: la sesión puede estar perfecta |
| `426` | `transient` | La app habla un `schema_version` que el BFF ya no entiende, o no manda sobre. Los jobs quedan en `PENDING` y suben solos cuando el colportor actualiza. `code`: `SCHEMA_VERSION_VIEJA` |

Una respuesta que no se puede parsear se trata como `transient`: es un bug del
servidor, y mandar a `INVALID` un job válido porque el BFF devolvió basura sería
peor que reintentarlo.

## Por qué el `426` es transitorio y no un error de payload

Una app vieja no manda datos malos: manda datos buenos en un formato que el
servidor ya no interpreta. Si el `426` fuera `payload`, los jobs irían a
`INVALID` —a la cola de error, sin reintento automático— y el colportor vería
sus propias ventas marcadas como un error suyo. Al actualizar la app no
subirían solas: habría que apretar "reintentar" una por una.

Como `transient`, quedan en `PENDING` y el primer ciclo después de actualizar
las sube. Lo que sí necesita la UI es distinguirlo de "sin red", y para eso está
el `code`: la pantalla puede decir "actualizá la app" en vez de "esperando
conexión".

Un sobre **ausente** se trata igual que uno viejo: un cliente que no lo manda es
anterior a v1.0 del cable. Un sobre **presente y mal formado** sí es `400`: eso
no es una app vieja, es un cliente que no cumple.
