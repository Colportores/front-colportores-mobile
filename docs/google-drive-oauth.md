# Registro de la app en Google para el respaldo en Drive (#179)

Caso: la colportora pierde el teléfono y recupera sus ventas desde la copia cifrada en su propio Google Drive ([ADR-006](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-006-cifrado-db-local-y-backup-e2e-en-drive.md), HU-SYNC-004). La app no inicia sesión con Google: la cuenta de Google se usa solo para autorizar el respaldo.

Este documento deja lo que hace falta para que Google apruebe la app. El alta en Google Cloud la hace Cristian con su cuenta (decisión del 23/10, «Drive y FCM»); el código llega con #184 y #185 en el S11. Si Google no aprueba a tiempo se avisa y se sigue con el resto del plan.

## Lo que se le pide a Google

| Dato | Valor |
|---|---|
| Alcance (scope) | `https://www.googleapis.com/auth/drive.appdata` y ningún otro |
| Qué da ese alcance | Ver, crear y borrar **solo los archivos de la propia app** en la carpeta oculta `appDataFolder` del Drive de la usuaria. No ve ni toca sus otros archivos. |
| Clasificación | No sensible, según la tabla de alcances de Drive API (confirmarlo en la consola, sección «Acceso a los datos»). Con solo alcances no sensibles no hay revisión de seguridad ni video de demostración: queda la verificación de marca (nombre, logo, página de inicio y política de privacidad). |
| Tipo de usuario | Externo (cualquier cuenta de Google) |
| Estado de publicación | **En producción** antes de usarla con colportoras reales. En «Prueba» el tope es de 100 usuarias de prueba cargadas a mano y el permiso vence a los 7 días, con lo que el respaldo nocturno se cortaría solo. |

### Justificación del alcance (texto para el formulario)

> Colportores guarda en el teléfono datos de las personas visitadas (nombre, teléfono, notas). Esos datos no suben a nuestros servidores. Para que la colportora no los pierda si pierde o cambia de teléfono, la app guarda una copia en su propio Google Drive. La copia se cifra en el teléfono, antes de subirla, con una clave que solo conoce la usuaria: Google ni la organización pueden leerla. Usamos únicamente `drive.appdata`, que da acceso a una carpeta oculta que pertenece a la app, sin acceso a ningún otro archivo del Drive. No pedimos `drive` ni `drive.file`.

### Uso de los datos (para la pantalla de consentimiento)

- La app no recibe ni guarda el correo, el nombre ni la foto de la cuenta de Google: usa la cuenta solo para obtener permiso sobre `appDataFolder`. La sesión de la app sigue siendo correo y contraseña.
- Los archivos subidos son cifrados (AES-GCM, ADR-006). La organización no tiene copia de la clave.
- La usuaria puede desconectar Drive desde Configuración; los archivos ya subidos quedan en su Drive y los borra ella o la propia app (HU-AUTH-010).
- Texto previo al consentimiento dentro de la app (HU-SYNC-004): «La app va a guardar archivos cifrados (no legibles para Google) en una carpeta oculta de tu Drive. Solo esta app puede leerlos.»

## Pasos para Cristian (alta en Google Cloud)

1. Entrar a [Google Cloud Console](https://console.cloud.google.com/) con la cuenta de la organización y crear el proyecto `colportores` (esa cuenta queda como propietaria del proyecto: conviene que sea de la organización y no personal, y sumar una segunda como propietaria).
2. **APIs y servicios → Biblioteca:** habilitar «Google Drive API».
3. **Google Auth Platform → Marca** (pantalla de consentimiento):
   - Tipo de usuario: **Externo**.
   - Nombre de la app: `Colportores`.
   - Correo de asistencia y correo de contacto del desarrollador: un correo de la organización que se lea.
   - Logo: 120 × 120 px, el ícono de la app.
   - Página de inicio y **política de privacidad**: la dirección pública de la política (ver «Lo que falta de afuera»).
   - Dominios autorizados: el dominio de esas páginas.
4. **Acceso a los datos:** agregar solo `.../auth/drive.appdata` y pegar la justificación de arriba.
5. **Clientes** (credenciales OAuth 2.0), uno por plataforma:
   - **Android:** paquete `com.colportores.colportores_mobile` y la huella SHA-1 de la clave de firma. Hoy la app firma el release con la clave de debug (`android/app/build.gradle.kts`): hace falta la huella de la clave de firma real (la de la subida a Play y, si se usa Play App Signing, la que Google asigna) y la de debug para desarrollo. Cada huella es un cliente Android.
   - **iOS:** bundle id `com.colportores.colportoresMobile`. Anotar el ID de cliente y el «esquema URL invertido»: van en `ios/Runner/Info.plist` (riesgo R29 de HU-SYNC-004).
   - **Web:** si el plugin que elija #184 lo pide (`serverClientId` en las versiones nuevas de `google_sign_in`), un cliente de tipo «Aplicación web». Se confirma en #184.
6. **Publicar la app** (botón «Publicar» en la audiencia): pasar de «Prueba» a «En producción». Con solo alcances no sensibles no pide revisión; si pide verificación de marca, tarda de unos días a un par de semanas.
7. Guardar los ID de cliente en el gestor de secretos del proyecto (no en el repo) y avisar en #184 cuáles son. Los ID de cliente no son secretos, pero la clave de firma sí.

## Lo que falta de afuera (no lo resuelve este issue)

- **Política de privacidad publicada.** Google la exige en una dirección pública y estable. Está decidido (21/10, «Texto legal»): borrador nuestro, aprobado por legal, publicado por versión en GitHub Pages ([docs-organizacion#71](https://github.com/Colportores/docs-organizacion/issues/71), [front-colportores-mobile#386](https://github.com/Colportores/front-colportores-mobile/issues/386)). Hasta que exista, el paso 3 no se puede cerrar. La política tiene que nombrar el respaldo en Drive: qué se guarda, que va cifrado y que se desconecta cuando la usuaria quiera.
- **Dominio de esa página.** Riesgo: Google puede rechazar `*.github.io` como dominio autorizado, y la página de inicio y la política tienen que estar en un dominio que la organización pueda verificar. Se prueba en el paso 3; si la consola lo rechaza hace falta un dominio propio (ver el archivo de pendientes del PR).
- **Clave de firma de release de Android** (paso 5): sin ella no hay huella real que registrar.

## Qué viene después

- #184: autorización con `drive.appdata`, token en `secure_storage`, desconectar y estado «Reconectar Drive» (HU-SYNC-004) sobre el puerto `ArchivePort`/`DriveArchive` de `packages/sync_engine`.
- #185: respaldo incremental cifrado (HU-SYNC-005). #186: recuperación en otro teléfono. #187: push, por ADR-014.
