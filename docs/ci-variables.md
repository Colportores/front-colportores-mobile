# Variables y secretos de GitHub Actions (compilados y publicación)

Todo lo configurable de los workflows de despliegue sale de variables (`vars.*`) o secretos (`secrets.*`) de GitHub
Actions, por **environment**. No hay valores secretos en el repo (es público): acá solo hay nombres y ejemplos.

- **Staging** (`staging.yml`, push a `staging` o corrida manual): usa el environment `staging`. Todo es opcional: sin
  nada cargado sigue andando con los valores de siempre (Supabase dev vía las variables del repo, sufijo `.staging`,
  nombre «Colportores (staging)», firma de debug, pre-release de GitHub con el APK).
- **Production** (`production.yml`, push a `production`): usa el environment `production`. Nada es opcional salvo lo
  que dice la tabla; si falta algo el workflow **falla con un mensaje que dice qué variable falta y dónde cargarla**.
  Nunca cae a las variables de dev del repo: lee sus propios nombres `PRODUCTION_SUPABASE_*`, que no existen a nivel
  repositorio (las `SUPABASE_URL` / `SUPABASE_ANON_KEY` del repo son las del proyecto dev, y `vars.*` mezcla environment
  y repo, así que con los mismos nombres un olvido en el environment compilaría con la clave de dev).
- Ningún paso lee secretos en un PR ni en un fork: los workflows solo disparan por push a `staging` / `production` o a
  mano, y el evento `pull_request` de esos archivos no tiene jobs (solo registra el workflow).

Cómo cargar: Settings → Environments → `<entorno>` → Variables / Secrets, o por consola
(`gh variable set NOMBRE --env production --body valor`, `gh secret set NOMBRE --env production < archivo`).
Un environment pisa a las variables del repo (Settings → Secrets and variables → Actions → Variables).

## Tabla

| Nombre | Tipo | Environment | Para qué sirve | Obligatoria | Ejemplo (sin secretos) |
|---|---|---|---|---|---|
| `SUPABASE_URL` | variable | staging (y repositorio) | URL del proyecto Supabase dev al que se conecta el APK de staging | no (valen las del repo, hoy el proyecto dev; si no hay ninguna se compila sin conexión y avisa). Production no la lee | `https://abcdefghijklmnop.supabase.co` |
| `SUPABASE_ANON_KEY` | variable | staging (y repositorio) | Clave anónima del proyecto dev (pública por diseño, la autoridad es la RLS). Nunca la `service_role` | igual que la URL. Production no la lee | `sb_publishable_...` |
| `PRODUCTION_SUPABASE_URL` | variable | production | URL del proyecto Supabase de producción. Distinta de la de dev (el build falla si contiene el ref dev) | production: sí | `https://qrstuvwxyzabcdef.supabase.co` |
| `PRODUCTION_SUPABASE_ANON_KEY` | variable | production | Clave anónima del proyecto de producción (pública por diseño). Nunca la `service_role`; el build falla si es igual a la `SUPABASE_ANON_KEY` del repo | production: sí | `sb_publishable_...` |
| `APP_ENV` | variable | production | Marca de que el environment está configurado: tiene que valer `production` | production: sí | `production` |
| `COLPORTORES_APP_ID_SUFFIX` | variable | staging | Sufijo del `applicationId` para instalar al lado de otra app. `ninguno` fuerza vacío. Production no lo aplica (el `applicationId` tiene que coincidir con `PLAY_PACKAGE_NAME`) | no (`.staging`) | `.staging` |
| `COLPORTORES_APP_NAME` | variable | staging | Nombre en el lanzador. `ninguno` fuerza el de siempre. Production no lo aplica | no (`Colportores (staging)`) | `Colportores (staging)` |
| `SUPABASE_REF_DEV` | variable | production | Ref adicional que producción no puede usar. Se suma al de la demo (`ohdsavwpasfpapbyutrv`), que siempre se rechaza | no | `otroproyectodev` |
| `GOOGLE_SERVER_CLIENT_ID` | variable | staging, production | Cliente OAuth web para el respaldo en Drive (`docs/google-drive-oauth.md`) | no (default del código) | `1234-xxxx.apps.googleusercontent.com` |
| `SOPORTE_WHATSAPP`, `SOPORTE_WHATSAPP_VISIBLE` | variable | staging, production | WhatsApp de soporte y si se muestra | no (default del código) | `59899123456`, `true` |
| `LOG_LEVEL` | variable | staging, production | Nivel de logs | no (default del código) | `info` |
| `STAGING_PRERELEASE` | variable | staging | `false` = compila pero no crea el pre-release de GitHub | no (se crea) | `false` |
| `STAGING_PRERELEASE_NOTAS` | variable | staging | Texto extra en las notas del pre-release | no | `Probar el flujo de cierre` |
| `ANDROID_KEYSTORE_BASE64` | secreto | staging, production | Keystore `.jks` en base64 (`base64 -w0 archivo.jks`) | production: sí. staging: no (sin ella firma con la clave de debug del runner) | (secreto) |
| `ANDROID_KEYSTORE_PASSWORD` | secreto | staging, production | Contraseña de la keystore | con la keystore | (secreto) |
| `ANDROID_KEY_ALIAS` | secreto | staging, production | Alias de la clave | con la keystore | (secreto) |
| `ANDROID_KEY_PASSWORD` | secreto | staging, production | Contraseña de la clave | con la keystore | (secreto) |
| `PLAY_PACKAGE_NAME` | variable | production | `applicationId` de la app en Google Play | production: sí | `com.colportores.colportores_mobile` |
| `PLAY_TRACK` | variable | production | Pista de Play: `internal`, `alpha`, `beta` o `production` | no (`internal`) | `internal` |
| `PLAY_RELEASE_STATUS` | variable | production | `draft` (queda en borrador en la consola) o `completed` | no (`draft`) | `draft` |
| `PLAY_SERVICE_ACCOUNT_JSON` | secreto | production | JSON de la cuenta de servicio con permiso de publicar en la app | production: sí | (secreto) |

Si hay keystore, tienen que estar las cuatro; si falta alguna el build lo dice y no sigue.

## Qué cubre cada decisión pendiente (ci-despliegue p1–p4)

Decisión de Cristian (03/11): se resuelven por variables de Actions. Cargar el environment correspondiente deja cada
una lista; el workflow no pide nada más y ninguna implica una cuenta o un costo que este repo decida.

- **p1, dónde se baja el APK de staging.** Hoy: pre-release de GitHub `staging-<n>` con el APK, sin cuentas (el repo es
  público: el APK queda descargable y apunta al Supabase dev con datos simulados, clave pública). Cuando exista el
  proyecto Firebase (FCM, ADR-014) se agrega App Distribution con una cuenta de servicio como secreto del environment
  `staging`; mientras tanto `STAGING_PRERELEASE=false` apaga el pre-release si se prefiere solo el artefacto de Actions.
- **p2, firma y sufijo de staging.** Sufijo y nombre: `COLPORTORES_APP_ID_SUFFIX` y `COLPORTORES_APP_NAME` (ya andan con
  sus defaults). Firma: cargar los cuatro `ANDROID_KEY*` como secretos del environment `staging` con una keystore de
  prueba; así el APK se actualiza sin desinstalar. Si se quiere respaldo en Drive en staging, el cliente OAuth Android
  se crea para `…colportores_mobile.staging` con el SHA-1 de esa keystore (`docs/google-drive-oauth.md`).
- **p3, producción en Google Play.** Con el environment `production` cargado (`APP_ENV`, `PRODUCTION_SUPABASE_*`, firma,
  `PLAY_PACKAGE_NAME`, `PLAY_SERVICE_ACCOUNT_JSON`) cada merge a `production` compila el AAB y lo sube a la pista
  `PLAY_TRACK` (interno) en borrador. La cuenta de Play, la keystore de subida y la cuenta de servicio las crea Cristian;
  la primera versión de la app se sube a mano desde Play Console. Para un canal interno en vez de Play basta no cargar
  `PLAY_SERVICE_ACCOUNT_JSON` y bajar el AAB/APK del artefacto del workflow.
- **p4**, hosting del panel de producción: es del repo `front-coordinadores-web` (`docs/ci-variables.md` de ese repo).
